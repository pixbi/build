{-# LANGUAGE TemplateHaskell #-}

module Development.Duplo.Config
  ( BuildConfig(..)
  , isInDev
  , appName
  , appVersion
  , appId
  , cwd
  , duploPath
  , env
  , mode
  , bin
  , input
  , utilPath
  , appPath
  , devPath
  , assetsPath
  , targetPath
  ) where

import Development.Shake
import Control.Lens hiding (Action)
import Control.Lens.TH (makeLenses)

data BuildConfig = BuildConfig { _appName    :: String
                               , _appVersion :: String
                               , _appId      :: String
                               , _cwd        :: String
                               , _duploPath  :: FilePath
                               , _env        :: String
                               , _mode       :: String
                               , _bin        :: FilePath
                               , _input      :: String
                               , _utilPath   :: FilePath
                               , _appPath    :: FilePath
                               , _devPath    :: FilePath
                               , _assetsPath :: FilePath
                               , _targetPath :: FilePath
                               }

makeLenses ''BuildConfig

isInDev :: BuildConfig -> Bool
isInDev config = config ^. env == "dev"