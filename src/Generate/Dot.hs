{-# LANGUAGE OverloadedStrings #-}

module Generate.Dot where

import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Text.IO as Tio
import qualified Data.Maybe as MA
import Types
import Generate.Types
import                  System.FilePath.Posix   ((</>),(<.>))
import Utils
import                  System.Directory


generateDot :: ClientServerApp -> FilePath -> Bool -> IO ()
generateDot (startCp
            ,netLst
            ,cExtraTlst
            ) fp renderTypes = 
    let
        
    in do
        createDirectoryIfMissing True (fp </> "Diagrams")
        mapM_ (\net -> writeIfNew 0 (fp </> "Diagrams" </> (T.unpack $ getNetName net) <.> "dot") (generateNetDot net)) netLst
    

generateNetDot :: Net -> T.Text
generateNetDot
        (Net name startingPlace places transitions plugins)
        =
    let
        nodes :: T.Text
        nodes =
            let
                placeNodes =
                    map (\place -> T.concat["  ",getPlaceName place,"node [label=\"",getPlaceName place,"\",shape=circle]"]) places
                transitionNodes =
                    map (\trans -> T.concat["  ",getTransitionName trans,"node [label=\"",getTransitionName trans,"\",shape=box]"]) transitions
            in
                T.unlines $
                    placeNodes ++ transitionNodes

        transitionsTxt :: T.Text
        transitionsTxt =
            let
                oneConnection :: T.Text -> (T.Text, Maybe (T.Text, Constructor)) -> T.Text
                oneConnection transName (from,mTo) =
                    case mTo of
                        Just (to, (msgName,edts)) ->
                            let
                                sameTailName = 
                                    T.concat[from,msgName,to]
                            in
                            T.unlines
                                [
                                    T.concat["  ",transName,"node -> ",from,"node [arrowhead=none",",sametail=",sameTailName,"]"]
                                ,   T.concat["  ",transName,"node -> ",to,"node [label=\"", msgName,"\"",",sametail=",sameTailName,"]"]
                                ]
                        Nothing ->
                            let
                                sameTailName = 
                                    T.concat[from,"same"]
                            in   
                            T.unlines
                            [
                                T.concat["  ",transName,"node -> ",from,"node [arrowhead=none",",sametail=",sameTailName,",style=dashed]"]
                            ,   T.concat["  ",transName,"node -> ",from,"node [","sametail=",sameTailName,",","style=dashed]"]
                            ]

                clientTrans :: T.Text -> T.Text -> T.Text
                clientTrans transition place = T.concat[" ",transition,"node -> ",place,"node [color=\"blue\"]"]

                cmdTrans :: T.Text -> T.Text -> T.Text
                cmdTrans transition place =
                    if (T.head transition) == '_'
                        then T.concat[" ",transition,"_ [label=\"\"]\n",
                            " ",transition,"_ -> ",place,"node [color=\"red\"]"]
                    else if (T.head place) == '_'
                        then T.concat[" ",transition,"node -> ",place,"_ [color=\"red\"]"]
                    else T.concat[" ",transition,"node -> ",place,"node [color=\"red\"]"]

                oneTrans :: Transition -> T.Text
                oneTrans (Transition _ (transName,_) connections cmd) =
                    T.unlines $ map (oneConnection $ transName) connections
                oneTrans (ClientTransition (n,et) place) =
                    clientTrans n place
                oneTrans (CmdTransition (msg,_) connection place) =
                    T.concat [(cmdTrans connection msg),"\n",
                              (cmdTrans (T.append "_" msg) place),"\n",
                              (cmdTrans msg (T.append "_" msg))]

                allTransitions =
                    T.unlines $ map oneTrans transitions
            in
                allTransitions
    in
    T.unlines 
    [
        "digraph D {"
    ,   nodes
    ,   ""
    ,   transitionsTxt
    ,   "}"
    ]
