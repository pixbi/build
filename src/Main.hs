import Control.Applicative ((<$>))
import Data.Maybe (fromMaybe)
import Development.Duplo.Styles as Styles
import Development.Duplo.Utilities (logAction)
import Development.Shake
import Development.Shake.FilePath ((</>))
import System.FilePath.Posix (makeRelative)
{-import System.Directory (getCurrentDirectory)-}
import System.Environment (lookupEnv, getArgs)
{-import System.Environment.Executable (splitExecutablePath)-}
{-import Data.String.Utils-}
import Development.Duplo.ComponentIO
         ( appName
         , appVersion
         , appRepo
         , appId
         )
{-import Development.Duplo.Files-}
import Development.Duplo.Markups as Markups
import Development.Duplo.Scripts as Scripts
import Development.Duplo.Static as Static
{-import Development.Shake.Command-}
{-import Development.Shake.Util-}
{-import System.FSNotify (withManager, watchTree)-}
{-import Filesystem (getWorkingDirectory)-}
{-import Filesystem.Path (append)-}
{-import Filesystem.Path.CurrentOS (decodeString)-}
{-import Control.Concurrent (forkIO)-}
import qualified Development.Duplo.Config as C
import Control.Monad (zipWithM_, filterM, liftM)
import Control.Applicative ((<$>), (<*>))
import Data.List (transpose)

main :: IO ()
main = do
  -- Command-line arguments
  args <- getArgs
  let shakeCommand = head args

  -- Environment - e.g. dev, staging, live
  duploEnv  <- fromMaybe "" <$> lookupEnv "DUPLO_ENV"
  -- Build mode, for dependency selection
  duploMode <- fromMaybe "" <$> lookupEnv "DUPLO_MODE"
  -- Application parameter
  duploIn   <- fromMaybe "" <$> lookupEnv "DUPLO_IN"
  -- Current directory
  cwd       <- fromMaybe "" <$> lookupEnv "CWD"
  -- Duplo directory
  duploPath <- fromMaybe "" <$> lookupEnv "DUPLO_PATH"

  -- Paths to various relevant directories
  let nodeModulesPath = duploPath </> "node_modules/.bin/"
  let utilPath        = duploPath </> "util/"
  let appPath         = cwd </> "app/"
  let assetsPath      = appPath </> "assets/"
  let targetPath      = cwd </> "public/"

  -- What to build
  let targetScript = targetPath </> "index.js"
  let targetStyle  = targetPath </> "index.css"
  let targetMarkup = targetPath </> "index.html"

  -- Gather information about this project
  appName'    <- appName
  appVersion' <- appVersion
  appId'      <- appId

  -- Report back what's given for confirmation
  putStr $ ">> Parameters\n"
        ++ "Application name                   : "
        ++ appName' ++ "\n"
        ++ "Application version                : "
        ++ appVersion' ++ "\n"
        ++ "Component.IO repo ID               : "
        ++ appId' ++ "\n"
        ++ "Current working directory          : "
        ++ cwd ++ "\n"
        ++ "duplo is installed at              : "
        ++ duploPath ++ "\n"
        ++ "\n"
        ++ ">> Environment Variables\n"
        ++ "Runtime environment - `DUPLO_ENV`  : "
        ++ duploEnv ++ "\n"
        ++ "Build mode          - `DUPLO_MODE` : "
        ++ duploMode ++ "\n"
        ++ "App parameters      - `DUPLO_IN`   : "
        ++ duploIn ++ "\n"
        ++ "\n"

  -- Construct environment
  let buildConfig = C.BuildConfig { C._appName    = appName'
                                  , C._appVersion = appVersion'
                                  , C._appId      = appId'
                                  , C._cwd        = cwd
                                  , C._duploPath  = duploPath
                                  , C._env        = duploEnv
                                  , C._mode       = duploMode
                                  , C._bin        = utilPath
                                  , C._input      = duploIn
                                  , C._utilPath   = utilPath
                                  , C._appPath    = appPath
                                  , C._assetsPath = assetsPath
                                  , C._targetPath = targetPath
                                  }

  shake shakeOptions $ do
    targetScript *> Scripts.build buildConfig
    targetStyle  *> Styles.build cwd nodeModulesPath
    targetMarkup *> Markups.build cwd nodeModulesPath

    -- Manually bootstrap Shake
    action $ do
      need [shakeCommand]

    -- Handling static assets
    (Static.qualify buildConfig) &?> \ outs -> do
      -- Convert to relative paths for copying
      let filesRel = fmap (makeRelative targetPath) outs

      -- Look in assets directory
      let assets = fmap (assetsPath ++) filesRel

      -- Log
      let repeat'  = replicate $ length assets
      let messages = transpose [ (repeat' "Copying ")
                               , assets
                               , (repeat' " to ")
                               , outs
                               ]
      mapM_ (putNormal . concat) messages

      -- Copy all files
      zipWithM_ copyFileChanged assets outs

    "static" ~> Static.build buildConfig

    "clean" ~> do
      logAction "Cleaning built files"
      cmd "rm" ["-rf", targetPath]

    "version" ~> do
      return ()

    "bump" ~> do
      logAction "Bumping version"

    "build" ~> do
      need [ targetScript
           , targetStyle
           , targetMarkup
           , "static"
           ]

      logAction "Build completed"
