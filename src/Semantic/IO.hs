{-# LANGUAGE DeriveAnyClass, DeriveDataTypeable, DuplicateRecordFields, GADTs, ScopedTypeVariables, TypeOperators, UndecidableInstances #-}
module Semantic.IO
  ( Destination(..)
  , Files
  , Handle(..)
  , IO.IOMode(..)
  , NoLanguageForBlob(..)
  , Source(..)
  , catchException
  , findFiles
  , findFilesInDir
  , getHandle
  , isDirectory
  , languageForFilePath
  , noLanguageForBlob
  , openFileForReading
  , readBlob
  , readBlobPairs
  , readBlobPairsFromHandle
  , readBlobs
  , readBlobsFromDir
  , readBlobsFromHandle
  , readFile
  , readFilePair
  , readProject
  , readProjectFromPaths
  , rethrowing
  , runFiles
  , stderr
  , stdin
  , stdout
  , write
  ) where

import qualified Control.Exception as Exc
import           Control.Monad.Effect
import           Control.Monad.Effect.Exception
import           Control.Monad.IO.Class
import           Data.Aeson
import qualified Data.Blob as Blob
import           Data.Bool
import           Data.Project
import qualified Data.ByteString as B
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy as BL
import           Data.Language
import           Data.Source (fromBytes, fromText)
import           Prelude hiding (readFile)
import           Prologue hiding (MonadError (..), fail)
import           System.Directory (doesDirectoryExist)
import qualified System.Directory.Tree as Tree
import           System.Directory.Tree (AnchoredDirTree(..))
import           System.Exit
import           System.FilePath
import           System.FilePath.Glob
import qualified System.IO as IO
import           Text.Read

-- | Read a utf8-encoded file to a 'Blob'.
readFile :: forall m. MonadIO m => File -> m (Maybe Blob.Blob)
readFile (File "/dev/null" _) = pure Nothing
readFile (File path language) = do
  raw <- liftIO (Just <$> B.readFile path)
  pure $ Blob.sourceBlob path language . fromBytes <$> raw

readFilePair :: forall m. MonadIO m => File -> File -> m Blob.BlobPair
readFilePair a b = Join <$> join (maybeThese <$> readFile a <*> readFile b)

maybeThese :: Monad m => Maybe a -> Maybe b -> m (These a b)
maybeThese a b = case (a, b) of
  (Just a, Nothing) -> pure (This a)
  (Nothing, Just b) -> pure (That b)
  (Just a, Just b)  -> pure (These a b)
  _                 -> fail "expected file pair with content on at least one side"

isDirectory :: MonadIO m => FilePath -> m Bool
isDirectory path = liftIO (doesDirectoryExist path)

-- | Return a language based on a FilePath's extension, or Nothing if extension is not found or not supported.
languageForFilePath :: FilePath -> Maybe Language
languageForFilePath = languageForType . takeExtension

-- | Read JSON encoded blob pairs from a handle.
readBlobPairsFromHandle :: MonadIO m => Handle 'IO.ReadMode -> m [Blob.BlobPair]
readBlobPairsFromHandle = fmap toBlobPairs . readFromHandle
  where
    toBlobPairs :: BlobDiff -> [Blob.BlobPair]
    toBlobPairs BlobDiff{..} = toBlobPair <$> blobs
    toBlobPair blobs = toBlob <$> blobs

-- | Read JSON encoded blobs from a handle.
readBlobsFromHandle :: MonadIO m => Handle 'IO.ReadMode -> m [Blob.Blob]
readBlobsFromHandle = fmap toBlobs . readFromHandle
  where toBlobs BlobParse{..} = fmap toBlob blobs

readBlobFromPath :: MonadIO m => File -> m Blob.Blob
readBlobFromPath file = do
  maybeFile <- readFile file
  maybe (fail ("cannot read '" <> show file <> "', file not found or language not supported.")) pure maybeFile

readProjectFromPaths :: MonadIO m => Maybe FilePath -> FilePath -> Language -> [FilePath] -> m Project
readProjectFromPaths maybeRoot path lang excludeDirs = do
  isDir <- isDirectory path
  let (filterFun, entryPoints, rootDir) = if isDir
      then (id, [], fromMaybe path maybeRoot)
      else (filter (/= path), [toFile path], fromMaybe (takeDirectory path) maybeRoot)

  paths <- liftIO $ filterFun <$> findFilesInDir rootDir exts excludeDirs
  pure $ Project rootDir (toFile <$> paths) lang entryPoints excludeDirs
  where
    toFile path = File path (Just lang)
    exts = extensionsForLanguage lang

-- Recursively find files in a directory.
findFilesInDir :: forall m. MonadIO m => FilePath -> [String] -> [FilePath] -> m [FilePath]
findFilesInDir path exts excludeDirs = do
  _:/dir <- liftIO $ Tree.build path
  pure $ (onlyFiles . Tree.filterDir (withExtensions exts) . Tree.filterDir (notIn excludeDirs)) dir
  where
    -- Build a list of only FilePath's (remove directories and failures)
    onlyFiles (Tree.Dir _ fs)   = concatMap onlyFiles fs
    onlyFiles (Tree.Failed _ _) = []
    onlyFiles (Tree.File _ f)   = [f]

    -- Predicate for Files with one of the extensions in 'exts'.
    withExtensions exts (Tree.File n _)
      | takeExtension n `elem` exts = True
      | otherwise                   = False
    withExtensions _ _              = True

    -- Predicate for contents NOT in a directory
    notIn dirs (Tree.Dir n _)
      | (x:_) <- n, x == '.' = False -- Don't include directories that start with '.'.
      | n `elem` dirs = False
      | otherwise = True
    notIn _ _ = True

readBlobsFromDir :: MonadIO m => FilePath -> m [Blob.Blob]
readBlobsFromDir path = do
  paths <- liftIO (globDir1 (compile "[^vendor]**/*[.rb|.js|.tsx|.go|.py]") path)
  let paths' = catMaybes $ fmap (\p -> File p . Just <$> languageForFilePath p) paths
  blobs <- traverse readFile paths'
  pure (catMaybes blobs)

readFromHandle :: (FromJSON a, MonadIO m) => Handle 'IO.ReadMode -> m a
readFromHandle (ReadHandle h) = do
  input <- liftIO $ BL.hGetContents h
  case eitherDecode input of
    Left e  -> liftIO (die (e <> ". Invalid input on " <> show h <> ", expecting JSON"))
    Right d -> pure d

toBlob :: Blob -> Blob.Blob
toBlob Blob{..} = Blob.sourceBlob path language' (fromText content)
  where language' = case language of
          "" -> languageForFilePath path
          _  -> readMaybe language


newtype BlobDiff = BlobDiff { blobs :: [BlobPair] }
  deriving (Show, Generic, FromJSON)

newtype BlobParse = BlobParse { blobs :: [Blob] }
  deriving (Show, Generic, FromJSON)

type BlobPair = Join These Blob

data Blob = Blob
  { path     :: FilePath
  , content  :: Text
  , language :: String
  }
  deriving (Show, Generic, FromJSON)

instance FromJSON BlobPair where
  parseJSON = withObject "BlobPair" $ \o -> do
    before <- o .:? "before"
    after <- o .:? "after"
    case (before, after) of
      (Just b, Just a)  -> pure $ Join (These b a)
      (Just b, Nothing) -> pure $ Join (This b)
      (Nothing, Just a) -> pure $ Join (That a)
      _                 -> fail "Expected object with 'before' and/or 'after' keys only"


-- | An exception indicating that we’ve tried to diff or parse a blob of unknown language.
newtype NoLanguageForBlob = NoLanguageForBlob FilePath
  deriving (Eq, Exception, Ord, Show, Typeable)

noLanguageForBlob :: Member (Exc SomeException) effs => FilePath -> Eff effs a
noLanguageForBlob blobPath = throwError (SomeException (NoLanguageForBlob blobPath))


readBlob :: Member Files effs => File -> Eff effs Blob.Blob
readBlob = send . Read . FromPath

-- | A task which reads a list of 'Blob's from a 'Handle' or a list of 'FilePath's optionally paired with 'Language's.
readBlobs :: Member Files effs => Either (Handle 'IO.ReadMode) [File] -> Eff effs [Blob.Blob]
readBlobs (Left handle) = send (Read (FromHandle handle))
readBlobs (Right paths) = traverse (send . Read . FromPath) paths

-- | A task which reads a list of pairs of 'Blob's from a 'Handle' or a list of pairs of 'FilePath's optionally paired with 'Language's.
readBlobPairs :: Member Files effs => Either (Handle 'IO.ReadMode) [Both File] -> Eff effs [Blob.BlobPair]
readBlobPairs (Left handle) = send (Read (FromPairHandle handle))
readBlobPairs (Right paths) = traverse (send . Read . FromPathPair) paths

readProject :: Member Files effs => Maybe FilePath -> FilePath -> Language -> [FilePath] -> Eff effs Project
readProject rootDir dir excludeDirs = send . ReadProject rootDir dir excludeDirs

findFiles :: Member Files effs => FilePath -> [String] -> [FilePath] -> Eff effs [FilePath]
findFiles dir exts = send . FindFiles dir exts

-- | A task which writes a 'B.Builder' to a 'Handle' or a 'FilePath'.
write :: Member Files effs => Destination -> B.Builder -> Eff effs ()
write dest = send . Write dest

data Handle mode where
  ReadHandle  :: IO.Handle -> Handle 'IO.ReadMode
  WriteHandle :: IO.Handle -> Handle 'IO.WriteMode

deriving instance Eq   (Handle mode)
deriving instance Show (Handle mode)

getHandle :: Handle mode -> IO.Handle
getHandle (ReadHandle  handle) = handle
getHandle (WriteHandle handle) = handle

stdin :: Handle 'IO.ReadMode
stdin = ReadHandle IO.stdin

stdout :: Handle 'IO.WriteMode
stdout = WriteHandle IO.stdout

stderr :: Handle 'IO.WriteMode
stderr = WriteHandle IO.stderr

openFileForReading :: FilePath -> IO (Handle 'IO.ReadMode)
openFileForReading path = ReadHandle <$> IO.openFile path IO.ReadMode

data Source blob where
  FromPath       :: File                -> Source Blob.Blob
  FromHandle     :: Handle 'IO.ReadMode -> Source [Blob.Blob]
  FromPathPair   :: Both File           -> Source Blob.BlobPair
  FromPairHandle :: Handle 'IO.ReadMode -> Source [Blob.BlobPair]

data Destination = ToPath FilePath | ToHandle (Handle 'IO.WriteMode)

-- | An effect to read/write 'Blob.Blob's from 'Handle's or 'FilePath's.
data Files out where
  Read        :: Source out -> Files out
  ReadProject :: Maybe FilePath -> FilePath -> Language -> [FilePath] -> Files Project
  FindFiles   :: FilePath -> [String] -> [FilePath] -> Files [FilePath]
  Write       :: Destination -> B.Builder -> Files ()

-- | Run a 'Files' effect in 'IO'.
runFiles :: Members '[Exc SomeException, IO] effs => Eff (Files ': effs) a -> Eff effs a
runFiles = interpret $ \ files -> case files of
  Read (FromPath path)         -> rethrowing (readBlobFromPath path)
  Read (FromHandle handle)     -> rethrowing (readBlobsFromHandle handle)
  Read (FromPathPair paths)    -> rethrowing (runBothWith readFilePair paths)
  Read (FromPairHandle handle) -> rethrowing (readBlobPairsFromHandle handle)
  ReadProject rootDir dir language excludeDirs -> rethrowing (readProjectFromPaths rootDir dir language excludeDirs)
  FindFiles dir exts excludeDirs -> rethrowing (findFilesInDir dir exts excludeDirs)
  Write (ToPath path)                   builder -> liftIO (IO.withBinaryFile path IO.WriteMode (`B.hPutBuilder` builder))
  Write (ToHandle (WriteHandle handle)) builder -> liftIO (B.hPutBuilder handle builder)


-- | Catch exceptions in 'IO' actions embedded in 'Eff', handling them with the passed function.
--
--   Note that while the type allows 'IO' to occur anywhere within the effect list, it must actually occur at the end to be able to run the computation.
catchException :: ( Exc.Exception e
                  , Member IO r
                  )
               => Eff r a
               -> (e -> Eff r a)
               -> Eff r a
catchException m handler = interpose pure (\ m yield -> send (Exc.try m) >>= either handler yield) m

-- | Lift an 'IO' action into 'Eff', catching and rethrowing any exceptions it throws into an 'Exc' effect.
rethrowing :: ( Member (Exc SomeException) r
              , Member IO r
              )
           => IO a
           -> Eff r a
rethrowing m = catchException (liftIO m) (throwError . toException @SomeException)
