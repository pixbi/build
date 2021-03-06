{-# LANGUAGE ScopedTypeVariables #-}

module Development.Duplo.Scripts where

import           Control.Applicative                    ((<$>), (<*>))
import           Control.Exception                      (SomeException (..),
                                                         throw)
import           Control.Lens                           hiding (Action)
import           Control.Monad                          (filterM)
import           Control.Monad.Trans.Class              (lift)
import           Control.Monad.Trans.Maybe              (MaybeT (..))
import           Data.Function                          (on)
import           Data.List                              (intercalate, nubBy)
import           Data.Text.Format                       (left)
import           Data.Text.Lazy                         (Text, pack, replace,
                                                         splitOn, unpack)
import           Data.Text.Lazy.Builder                 (toLazyText)
import           Development.Duplo.Component            (extractCompVersions)
import qualified Development.Duplo.Component            as CM
import           Development.Duplo.Files                (File (..), pseudoFile)
import           Development.Duplo.JavaScript.Order     (order)
import qualified Development.Duplo.Types.Config         as TC
import           Development.Duplo.Types.JavaScript
import           Development.Duplo.Utilities            (CompiledContent,
                                                         compile, createIntermediaryDirectories,
                                                         expandDeps,
                                                         expandPaths,
                                                         headerPrintSetter,
                                                         logStatus)
import           Development.Shake
import           Development.Shake.FilePath             ((</>))
import qualified Language.JavaScript.Parser             as JS
import           Language.JavaScript.Parser.SrcLocation (TokenPosn (..))
import           Text.Regex                             (matchRegex, mkRegex)

-- | How many lines to display around the source of error (both ways).
errorDisplayRange :: Int
errorDisplayRange = 20

-- | Build scripts
      -- The environment
build :: TC.BuildConfig
      -- The output file
      -> FilePath
      -- Doesn't need anything in return
      -> CompiledContent ()
build config out = do
  liftIO $ logStatus headerPrintSetter "Building scripts"

  let cwd         = config ^. TC.cwd
  let util        = config ^. TC.utilPath
  let env         = config ^. TC.env
  let mode        = config ^. TC.mode
  let buildMode   = config ^. TC.buildMode
  let input       = config ^. TC.input
  let devPath     = config ^. TC.devPath
  let depsPath    = config ^. TC.depsPath
  let devCodePath = devPath </> "modules/index.js"
  let depIds      = config ^. TC.dependencies

  -- Preconditions
  lift $ createIntermediaryDirectories devCodePath

  -- Get dependencies dynamically to avoid removed dependencies to be
  -- included again, when reloading during development.
  dependencies <- liftIO $ CM.getDependencies $ case mode of
                                              "" -> Nothing
                                              a  -> Just a
  let makeDepId = unpack . replace "/" "-" . pack
  let depIds = map makeDepId dependencies

  -- These paths don't need to be expanded.
  let staticPaths = case buildMode of
                      "development" -> [ "dev/index" ]
                      "test"        -> [ "dev/index" ]
                      _             -> []
                 ++ [ "app/index" ]

  -- These paths need to be expanded by Shake.
  let depsToExpand id = [ "components/" ++ id ++ "/app/modules" ]
  -- Compile dev files in dev mode as well, taking precendence.
  let dynamicPaths = [ "app/modules" ]
                  ++ case buildMode of
                       "development" -> [ "dev/modules" ]
                       _             -> []
                  -- Build list only for dependencies.
                  ++ expandDeps depIds depsToExpand

  -- Merge both types of paths
  paths <- lift $ expandPaths cwd ".js" staticPaths dynamicPaths

  -- Make sure we hvae at least something
  let duploIn = if not (null input) then input else ""

  -- Figure out each component's version
  compVers <- lift $ extractCompVersions config

  -- Inject global/environment variables
  let envVars = "var DUPLO_ENV = '" ++ env ++ "';\n"
             -- Decode and parse in runtime to avoid having to deal with
             -- escaping.
             ++ "var DUPLO_IN = JSON.parse(window.atob('" ++ duploIn ++ "') || '{}' );\n"
             ++ "var DUPLO_VERSIONS = " ++ compVers ++ ";\n"

  -- Configure the compiler
  let compiler = (util </>) $ case buildMode of
                                "development" -> "scripts-dev.sh"
                                "test"        -> "scripts-dev.sh"
                                _             -> "scripts-optimize.sh"

  -- Create a pseudo file that contains the environment variables and
  -- prepend the file.
  let pre = return . (:) (pseudoFile { _fileContent = envVars })
  -- Reorder modules and print as string
  let prepareJs = JS.renderToString . order

  let post content = return
                   -- Handle error
                   $ either (handleParseError content) prepareJs
                   -- Parse
                   $ JS.parse content ""

  -- Build it
  compiled <- compile config compiler [] paths pre post

  -- Write it to disk
  lift $ writeFileChanged out compiled

-- | Given the original content as string and an error message that is
-- produced by `language-javascript` parser, throw an error.
handleParseError :: String -> String -> String
handleParseError content e = exception
  where
    linedContent = fmap unpack $ splitOn "\n" $ pack content
    lineCount = length linedContent
    lineNum = readParseError e
    -- Display surrounding lines
              -- Construct a list of target line numbers
    lineRange = take errorDisplayRange
              -- Turn into infinite list
              $ iterate (+ 1)
              -- Position the starting point
              $ lineNum - errorDisplayRange `div` 2
    showBadLine' = showBadLine linedContent lineNum
    -- Keep the line number in the possible domain.
    keepInRange = max 0 . min lineCount
    badLines = fmap (showBadLine' . keepInRange) lineRange
    -- Make sure we de-duplicate the lines.
    dedupe = nubBy ((==) `on` fst)
    -- Extract just the lines for display.
    badLinesDeduped = map snd $ dedupe badLines
    -- Construct the exception.
    exception = throw
      ShakeException { shakeExceptionTarget = ""
                     , shakeExceptionStack  = []
                     , shakeExceptionInner  = SomeException
                                            $ ParseException
                                              badLinesDeduped
                     }

-- | Given a file's lines, its line number, and the "target" line number
-- that caused the parse error, format it for human-readable output.
showBadLine :: [String] -> LineNumber -> LineNumber -> (LineNumber, String)
showBadLine allLines badLineNum lineNum = (lineNum, line')
  where
    line     = allLines !! lineNum
    -- Natural numbering for humans
    toString = unpack . toLazyText
    lineNum' = toString $ left 4 ' ' $ lineNum + 1
    marker   = if   lineNum == badLineNum
               then ">> " ++ lineNum'
               else "   " ++ lineNum'
    line'    = marker ++ " | " ++ line

-- | Because the parser's error isn't readable, we need to use RegExp to
-- extract what we need for debugging.
readParseError :: String -> LineNumber
readParseError e =
    case match of
      Just m  -> (read $ head m) :: Int
      Nothing -> throw $ InternalParserException e
  where
    regex = mkRegex "TokenPn [0-9]+ ([0-9]+) [0-9]+"
    match = matchRegex regex e
