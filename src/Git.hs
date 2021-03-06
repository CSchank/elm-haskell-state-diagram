{-# LANGUAGE OverloadedStrings #-}

module Git where

import Data.Aeson
import Network.HTTP.Simple
import Network.HTTP.Conduit
import Codec.Archive.Zip
import System.Directory
import Control.Monad (when)
import System.Console.ANSI
import qualified Data.Text.IO as TIO
import qualified Data.Text as T
import Data.List
import Control.Monad (unless,when)
import System.Exit (exitFailure, ExitCode(..))
import System.Process (readProcessWithExitCode)

newtype Zip = Zip String
    deriving (Show)

instance FromJSON Zip where
    parseJSON = withObject "Zip" $ \ v -> Zip <$> v .: "zipball_url"

newtype Release = Release String
    deriving (Show)

instance FromJSON Release where
    parseJSON = withObject "Release" $ \ v -> Release <$> v .: "tag_name"

requestWithUA :: String -> IO Request
requestWithUA url = do
    initReq <- parseRequest url
    return $ setRequestHeader "user-agent" [""] $ setRequestSecure True initReq

--getLatestRelease :: String -> IO Bytestring
getLatestRelease repo = do
    request <- requestWithUA $ "https://api.github.com/repos/" ++ repo ++ "/releases/latest"
    rel <- httpLBS request
    return $ getResponseBody rel

getRelease rel repo = do
    request <- requestWithUA $ "https://api.github.com/repos/" ++ repo ++ "/releases/tags/" ++ rel
    rel <- httpLBS request
    return $ getResponseBody rel

getLatestVersion :: IO (Maybe String)
getLatestVersion = do
    latestRelease <- getLatestRelease "cschank/petri-app-land"
    let version = decode latestRelease :: Maybe Release
    case version of
        Just (Release rel) ->
            return $ Just rel
        Nothing ->
            return Nothing

loadTemplates :: String -> IO ()
loadTemplates version = do
  latestRelease <- getRelease version "CSchank/PAL-templates"
  putStrLn $ "Downloading PAL templates " ++ version ++ "......"
  let mZip = decode latestRelease
  case mZip of
    Just (Zip url) -> do
      zipReq <- requestWithUA url
      zipBody <- httpLBS zipReq
      let zip = toArchive $ getResponseBody zipBody
      let root = head $ filesInArchive zip
      extractFilesFromArchive [OptDestination "."] zip
      exists <- doesDirectoryExist ".templates"
      when exists $ removeDirectoryRecursive ".templates"
      renamePath root ".templates"
    Nothing -> do
      setSGR [SetColor Foreground Vivid Red]
      putStrLn "Additional info: "
      putStrLn "Additional info: "
      putStrLn $ "Response: " ++ show latestRelease
      putStrLn
        "Potential solution: Try running `stack exec pal-update` to update your project to the newest version of PAL."
      putStrLn "Another potential problem: you may have exceeded the API limit. Wait an hour before trying again."
      putStrLn
        "If this persists, post an issue at https://github.com/cschank/petri-app-land/issues with the label help-request."
      putStrLn "Exiting..."
      setSGR [Reset]
      exitFailure
      setSGR [Reset]

checkVersion = do
    version <- T.unpack <$> TIO.readFile ".palversion"
    latest <- getLatestVersion
    case (latest, Just version == latest) of
        (Just _, True) -> do
            setSGR [SetColor Foreground Vivid Green]
            putStrLn $ "Using latest PAL version (" ++ version ++ ")."
            setSGR [Reset]
        (Just latest, False) -> do
            setSGR [SetColor Foreground Vivid Red]
            putStrLn $ "PAL version " ++ latest ++ " is available. (You have "++ version ++")."
            putStrLn "Use `stack exec pal-exe update` to update."
            setSGR [Reset]
        (Nothing, _) -> do
            setSGR [SetColor Foreground Vivid Red]
            putStrLn $ "Unable to perform version check (You have "++ version ++"). Try again later."
            setSGR [Reset]

-- from https://stackoverflow.com/a/5852820
replaceNth :: Int -> a -> [a] -> [a]
replaceNth _ _ [] = []
replaceNth n newVal (x:xs)
   | n == 0 = newVal:xs
   | otherwise = x:replaceNth (n-1) newVal xs

getPALVersion :: FilePath -> IO (Maybe T.Text)
getPALVersion file = do
  stackYaml <- T.lines <$> TIO.readFile "stack.yaml"
  let versionIdx = "#PALCOMMIT" `elemIndex` stackYaml
  return $ fmap (T.strip . (!!) stackYaml . (+1)) versionIdx

updatePAL :: IO ()
updatePAL = do
    latestRelease <- getLatestRelease "CSchank/petri-app-land"
    let mRel = decode latestRelease
    case mRel of
        Just (Release rel) -> do
            currentVersion <- T.unpack . head . T.lines <$> TIO.readFile ".palversion"
            if currentVersion == rel then do
                setSGR [SetColor Foreground Vivid Green]
                putStrLn $ "PAL is already on the latest version (" ++ rel ++ ")"
                setSGR [Reset]
            else do
                setSGR [SetColor Foreground Vivid Yellow]
                putStrLn $ "You are using an older version of PAL (" ++ currentVersion ++ ")."
                putStrLn $ "The newest version is " ++ rel ++ "."
                putStrLn $ "See changelog at https://github.com/CSchank/petri-app-land/releases/tag/" ++ rel ++ "."
                putStrLn $ "Update to version " ++ rel ++ "? (Y/N)"
                setSGR [Reset]

                resp <- getLine
                if resp == "y" || resp == "Y" then do
                    stackYaml <- T.lines <$> TIO.readFile "stack.yaml"
                    case "#PALCOMMIT" `elemIndex` stackYaml of
                        Just line -> do
                            let newYaml = replaceNth (line+1) (T.concat["  commit: ",T.pack rel]) stackYaml
                            TIO.writeFile "stack.yaml" $ T.unlines newYaml
                            loadTemplates rel -- download the PAL templates for this version
                            setSGR [SetColor Foreground Vivid Green]
                            putStrLn "Templates downloaded."
                            putStrLn "stack.yaml file updated to reflect new version of PAL"
                            TIO.writeFile ".palversion" $ T.pack rel
                            setSGR [Reset]
                            putStrLn "Building project with newest PAL version..."
                            (code, stdout, stderr) <- readProcessWithExitCode  "stack" ["build", "--no-terminal"] ""
                            case code of
                              ExitSuccess -> do
                                setSGR [SetColor Foreground Vivid Red]
                                putStrLn $ "Update complete. Version is now " ++ rel ++ "."
                                putStrLn "Run `stack exec pal-exe` to rebuild your project with the newest version of PAL."
                                putStrLn "Then rebuild your client and server."
                                setSGR [Reset]
                              ExitFailure _ -> do
                                setSGR [SetColor Foreground Vivid Red]
                                putStrLn "Unable to build your project."
                                putStrLn "Fix errors in specification and run `stack build` again."
                                putStrLn "Then run `stack exec pal-exe` to rebuild your project with the newest version of PAL."
                                putStrLn "Then rebuild your client and server."
                                setSGR [Reset]

                        Nothing -> do
                            setSGR [SetColor Foreground Vivid Red]
                            putStrLn "Could not find #PALCOMMIT in stack.yaml. Please replace your stack.yaml with the original one."
                            setSGR [Reset]
                else do
                    setSGR [SetColor Foreground Vivid Green]
                    putStrLn "Update aborted. Run `stack exec pal-exe update` again to update."
                    setSGR [Reset]
        Nothing -> do
            setSGR [SetColor Foreground Vivid Red]
            putStrLn "Error: Could not decode latest release from GitHub. You may have exceeded the API limit."
            setSGR [Reset]