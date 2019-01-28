module Static.Plugins where
import NewYouthHack.Static.Types as NewYouthHack

import Static.ServerTypes
import Static.Types
import Data.Maybe (fromJust)
import Control.Concurrent.STM (TQueue, atomically, writeTQueue)
import Data.TMap as TM (TMap,lookup)
import Utils.Utils as Utils

processCmd :: TQueue CentralMessage -> Maybe (Cmd NetTransition) -> NetTransition -> ServerState -> IO ()
processCmd centralMessageQueue mCmd nTrans state =
    case mCmd of
        Just cmd ->
            case nTrans of
                NewYouthHackTrans {} ->
                      Utils.processCmd cmd centralMessageQueue (fromJust $ TM.lookup $ serverState state :: NetState NewYouthHack.Player)


        Nothing -> return ()
