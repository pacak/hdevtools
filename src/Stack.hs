{-# LANGUAGE CPP #-}
module Stack
      ( -- * The bits of information needed from `stack`
        StackConfig (..)
      , findStackYaml
      , getStackConfig
      ) where

import Data.Char (isSpace)

#if __GLASGOW_HASKELL__ < 709
import Control.Applicative((<$>), (<*>))
import System.IO
#endif

import System.Process
import System.FilePath
import System.Directory
import Control.Monad (filterM)
import Control.Exception
import Types

-- TODO: Move into Types?
data StackConfig = StackConfig { stackYaml :: FilePath
                               , stackDist :: FilePath
                               , stackDbs  :: [FilePath]
                               , stackGhcLibDir :: FilePath
                               }
                   deriving (Eq, Show)

-- | Search for a @stack.yaml@ upwards in given file path tree.
findStackYaml :: FilePath -> IO (Maybe FilePath)
findStackYaml = fmap (fmap trim) . execInPath "stack path --config-location"

-- | Run @stack path@ to compute @StackConfig@
getStackConfig :: CommandExtra -> IO (Maybe StackConfig)
getStackConfig CommandExtra { ceStackYamlPath = Nothing } = return Nothing
getStackConfig CommandExtra { ceStackYamlPath = Just p } = do
    dbs <- getStackDbs root
    dist <- getStackDist root
    ghcLibDir <- getStackGhcLibDir root
    return $ StackConfig p <$> dist
                           <*> dbs
                           <*> ghcLibDir
  where
    root = takeDirectory p

getStackGhcLibDir :: FilePath -> IO (Maybe FilePath)
getStackGhcLibDir = fmap (fmap takeDirectory) . execInPath "stack path --global-pkg-db"

--------------------------------------------------------------------------------
getStackDist :: FilePath -> IO (Maybe FilePath)
--------------------------------------------------------------------------------
getStackDist p = (trim <$>) <$> execInPath cmd p
  where
    cmd        = "stack path --dist-dir"
    -- dir        = takeDirectory p
    -- splice     = (dir </>) . trim

--------------------------------------------------------------------------------
getStackDbs :: FilePath -> IO (Maybe [FilePath])
--------------------------------------------------------------------------------
getStackDbs p = do mpp <- execInPath cmd p
                   case mpp of
                       Just pp -> Just <$> extractDbs pp
                       Nothing -> return Nothing
  where
    cmd       = "stack path --ghc-package-path"

extractDbs :: String -> IO [FilePath]
extractDbs = filterM doesDirectoryExist . stringPaths

stringPaths :: String -> [String]
stringPaths = splitBy ':' . trim

--------------------------------------------------------------------------------
-- | Generic Helpers
--------------------------------------------------------------------------------

splitBy :: Char -> String -> [String]
splitBy c str
  | null str' = [x]
  | otherwise = x : splitBy c (tail str')
  where
    (x, str') = span (c /=) str

trim :: String -> String
trim = f . f
   where
     f = reverse . dropWhile isSpace

#if __GLASGOW_HASKELL__ < 709
execInPath :: String -> FilePath -> IO (Maybe String)
execInPath cmd p = do
    eIOEstr <- try $ createProcess prc :: IO (Either IOError ProcH)
    case eIOEstr of
        Right (_, Just h, _, _)  -> Just <$> getClose h
        Right (_, Nothing, _, _) -> return Nothing
        -- This error is most likely "/bin/sh: stack: command not found"
        -- which is caused by the package containing a stack.yaml file but
        -- no stack command is in the PATH.
        Left _  -> return Nothing
  where
    prc          = (shell cmd) { cwd = Just $ takeDirectory p }

getClose :: Handle -> IO String
getClose h = do
  str <- hGetContents h
  hClose h
  return str

type ProcH = (Maybe Handle, Maybe Handle, Maybe Handle, ProcessHandle)

-- Not deleting this because this is likely more robust than the above! (but
-- only works on process-1.2.3.0 onwards

#else
execInPath :: String -> FilePath -> IO (Maybe String)
execInPath cmd p = do
    eIOEstr <- try $ readCreateProcess prc "" :: IO (Either IOError String)
    return $ case eIOEstr of
        Right s -> Just s
        -- This error is most likely "/bin/sh: stack: command not found"
        -- which is caused by the package containing a stack.yaml file but
        -- no stack command is in the PATH.
        Left _  -> Nothing
  where
    prc          = (shell cmd) { cwd = Just p }
#endif
