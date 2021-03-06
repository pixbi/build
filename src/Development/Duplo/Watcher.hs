module Development.Duplo.Watcher where

import           Control.Concurrent      (ThreadId (..), forkFinally, forkIO,
                                          killThread, threadDelay)
import           Control.Concurrent.Chan (Chan, getChanContents, newChan,
                                          readChan)
import           Control.Exception       (try)
import           Control.Monad           (forever, unless, void, when)
import           Data.Foldable           (forM_)
import           Data.IORef              (IORef, newIORef, readIORef,
                                          writeIORef)
import           Data.Maybe              (fromJust, isJust)
import           Data.String             (fromString)
import           System.FilePath.Posix   (FilePath)
import           System.FSNotify         (Action, Debounce (..), Event,
                                          WatchConfig (..), watchTreeChan,
                                          withManagerConf)

-- | Given some paths to watch and something to do, watch every 100ms
-- without debouncing but would interrupt the action when there is a new
-- event.
watch :: IO () -> [FilePath] -> IO ()
watch onChange paths = do
    let watchConfig = WatchConfig { confDebounce = NoDebounce
                                  , confPollInterval = 100000
                                  , confUsePolling = False
                                  }

    -- We need a variable to store the currently executing handler.
    tidVar <- newIORef (Nothing :: Maybe ThreadId)

    -- We need a channel to prevent race condition when an event is
    -- triggered on multiple paths.
    chan <- newChan :: IO (Chan Event)
    -- Make it a stream
    let chanStream = getChanContents chan

    -- The handler needs special treatment capturing IO exceptions. The
    -- policy is simply to drop all exceptions because we have a lot of
    -- incoming requests.
    let exceptionHandler _ = return ()
    let handler = forkFinally onChange exceptionHandler

    -- Curry `handleEvent` to stay DRY
    let handleEvent' = handleEvent tidVar handler

    -- Make sure we handle the event with a channel to avoid race
    -- condition.
    forkIO $ chanStream >>= mapM_ (handleEvent' . Just)

    -- Start watching
    withManagerConf watchConfig $ \manager -> do
      let paths' = fmap fromString paths
      let always = const True
      let watch' p = watchTreeChan manager p always chan

      -- Always start an initial round
      void $ handleEvent' Nothing

      -- Watch for changes
      mapM_ watch' paths'

      -- Hibernate, for a year!
      forever $ threadDelay $ 1000000 * 60 * 60 * 24 * 365

-- | Interrupt the given thread and re-perform the action.
handleEvent :: IORef (Maybe ThreadId) -> IO ThreadId -> Maybe Event -> IO ()
handleEvent tidVar handler _ = do
    tid <- readIORef tidVar
    -- Kill existing thread
    forM_ tid killThread

    -- Perform action
    newTid <- handler
    -- Save thread ID
    writeIORef tidVar $ Just newTid
