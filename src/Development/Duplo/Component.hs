{-# LANGUAGE TemplateHaskell #-}

module Development.Duplo.Component
  ( appId
  , parseComponentId
  , readManifest
  , writeManifest
  , extractCompVersions
  ) where

import Control.Applicative ((<$>), (<*>))
import Development.Shake hiding (doesFileExist)
import Data.Text (breakOn)
import qualified Data.Text as T (unpack, pack)
import Data.ByteString.Lazy.Char8 (ByteString)
import qualified Data.ByteString.Lazy.Char8 as BS (unpack, pack)
import System.FilePath.Posix (splitDirectories)
import Control.Monad.Except (ExceptT(..), throwError)
import Control.Monad.Trans.Class (lift)
import System.Directory (doesFileExist)
import Development.Duplo.Types.AppInfo (AppInfo(..))
import qualified Development.Duplo.Types.AppInfo as AI
import Data.Aeson (encode, decode)
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.Maybe (fromJust)
import System.FilePath.FilePather.Find (findp)
import System.FilePath.FilePather.FilePathPredicate (always)
import System.FilePath.FilePather.FilterPredicate (filterPredicate)
import System.FilePath.FilePather.RecursePredicate (recursePredicate)
import System.FilePath.Posix (takeFileName)
import Data.Map (fromList)

type Version = (String, String)

-- | Each application must have a `component.json`
manifestName = "component.json"

readManifest :: ExceptT String IO AppInfo
readManifest = do
    exists <- liftIO $ doesFileExist manifestName

    if   exists
    then readManifest' manifestName
    else throwError $ "Manifest expected at " ++ manifestName

readManifest' :: FilePath -> ExceptT String IO AppInfo
readManifest' path = do
    manifest <- liftIO $ readFile path
    let maybeAppInfo = decode (BS.pack manifest) :: Maybe AppInfo

    case maybeAppInfo of
      Nothing -> ExceptT $ return $ Left $ "Unparsable manifest at " ++ path
      Just a  -> ExceptT $ return $ Right a

writeManifest :: AppInfo -> IO ()
writeManifest = (writeFile manifestName) . BS.unpack . encodePretty

-- | Get the app's Component.IO ID
appId :: AppInfo -> String
appId appInfo = parseRepoInfo $ splitDirectories $ AI.repo appInfo

-- | Parse the repo info into an app ID
parseRepoInfo :: [String] -> String
parseRepoInfo (owner : appRepo : _) = owner ++ "-" ++ appRepo
parseRepoInfo _ = ""

-- | Given a possible component ID, return the user and the repo
-- constituents
parseComponentId :: String -> Either String (String, String)
parseComponentId cId
  | repoL > 0 = Right ((T.unpack user), (T.unpack repo))
  | otherwise = Left $ "No component ID found with " ++ cId
  where
    (user, repo) = breakOn (T.pack "-") (T.pack cId)
    repoL = length $ T.unpack repo

-- | Given a path, find all the `component.json` and return a JSON string
extractCompVersions :: FilePath -> IO String
extractCompVersions path = do
    paths     <- getAllManifestPaths path
    manifests <- mapM ((fmap BS.pack) . readFile) paths
    let decodeManifest = \ x -> fromJust $ (decode x :: Maybe AppInfo)
    let manifests' = fmap (appInfoToVersion . decodeManifest) manifests
    return $ BS.unpack $ encode $ fromList manifests'

appInfoToVersion :: AppInfo -> Version
appInfoToVersion appInfo = ((AI.name appInfo), (AI.version appInfo))

-- | Given a path, find all the `component.json`s
getAllManifestPaths :: FilePath -> IO [FilePath]
getAllManifestPaths path =
    findp filterP always path
  where
    filterP   = filterPredicate matchName
    matchName = \ path t -> takeFileName path == takeFileName manifestName