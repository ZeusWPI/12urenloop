{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}
module CountVonCount.Web.Views
    ( index
    , monitor
    , management
    ) where

import Control.Monad (forM_)

import Text.Blaze (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

import CountVonCount.Persistence
import CountVonCount.Types

template :: Html -> Html -> Html
template title content = H.docTypeHtml $ do
    H.head $ do
        H.title title
        H.link ! A.rel "stylesheet" ! A.type_ "text/css"
            ! A.href "/css/screen.css"
    H.body $ do
        H.div ! A.id "header" $
            H.div ! A.id "navigation" $ do
                H.a ! A.href "/monitor"    $ "Monitor"
                H.a ! A.href "/management" $ "Management"
                H.a ! A.href "/bonus"      $ "Bonus"

        H.div ! A.id "content" $
            content

        H.div ! A.id "footer" $ ""

index :: Html
index = template "Home" "Hello world"

monitor :: [Team] -> Html
monitor teams = template "Monitor" $ do
    H.h1 "Scores"
    forM_ teams $ \team -> H.div $ do
        H.toHtml $ teamName team
        ": "
        H.toHtml $ teamLaps team

management :: [(Ref Team, Team, Maybe Baton)] -> [Baton] -> Html
management teams batons = template "Teams" $ do
    H.div ! A.id "secondary" $ do
        H.h1 "Free batons"
        forM_ batons $ \baton -> H.div ! A.class_ "baton" $ do
            H.toHtml $ batonName baton
            " ("
            H.unsafeByteString $ batonMac baton
            ")"

    H.h1 "Teams"
    forM_ teams $ \(ref, team, assigned) -> H.div ! A.class_ "team" $ do
        let assignUri = "/team/" ++ refToString ref ++ "/assign"

        H.toHtml $ teamName team

        H.form ! A.action (H.toValue assignUri) ! A.method "post" $ do
            H.select ! A.name "baton" $ do
                case assigned of
                    Just baton ->
                        H.option ! A.value (macValue baton)
                                 ! A.selected "selected" $
                            H.toHtml (batonName baton)
                    _          ->
                        H.option ! A.value "" ! A.selected "selected" $ ""

                forM_ batons $ \baton ->
                    H.option ! A.value (macValue baton) $
                        H.toHtml (batonName baton)
                
            H.input ! A.type_ "submit" ! A.value "Assign"
  where
    macValue = H.unsafeByteStringValue . batonMac