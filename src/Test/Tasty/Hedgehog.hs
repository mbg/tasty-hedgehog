-- | This package lets you test Hedgehog properties with tasty.
--
-- Typical usage would look like this:
--
-- @
-- testGroup "tasty-hedgehog tests" [
--    testProperty "reverse involutive" prop_reverse_involutive
--  , testProperty "sort idempotent"    prop_sort_idempotent
--  ]
-- @
--
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Test.Tasty.Hedgehog (
    testProperty
  -- * Options you can pass in via tasty
  , HedgehogReplay(..)
  , HedgehogShowReplay(..)
  , HedgehogTestLimit(..)
  , HedgehogDiscardLimit(..)
  , HedgehogShrinkLimit(..)
  , HedgehogShrinkRetries(..)
  , HedgehogUseColor(..)
  ) where

import Data.Maybe (fromMaybe)
import Data.Typeable

import qualified Test.Tasty.Providers as T
import Test.Tasty.Options

import Hedgehog
import Hedgehog.Internal.Config (UseColor(..))
import Hedgehog.Internal.Property
import Hedgehog.Internal.Runner as H
import Hedgehog.Internal.Report
import Hedgehog.Internal.Seed as Seed

data HP = HP PropertyName Property
  deriving (Typeable)

-- | Create a 'Test' from a Hedgehog property
testProperty :: T.TestName -> PropertyName -> Property -> T.TestTree
testProperty name propName prop = T.singleTest name (HP propName prop)

-- | The replay token to use for replaying a previous test run
newtype HedgehogReplay = HedgehogReplay (Maybe (Size, Seed))
  deriving (Typeable)

instance IsOption HedgehogReplay where
  defaultValue = HedgehogReplay Nothing
  parseValue v = HedgehogReplay . Just <$> replay
    -- Reads a replay token in the form "{size} {seed}"
    where replay = (,) <$> safeRead (unwords size) <*> safeRead (unwords seed)
          (size, seed) = splitAt 2 $ words v
  optionName = return "hedgehog-replay"
  optionHelp = return "Replay token to use for replaying a previous test run"

-- | If a test case fails, show a replay token for replaying tests
newtype HedgehogShowReplay = HedgehogShowReplay Bool
  deriving (Typeable)

instance IsOption HedgehogShowReplay where
  defaultValue = HedgehogShowReplay True
  parseValue = fmap HedgehogShowReplay . safeRead
  optionName = return "hedgehog-show-replay"
  optionHelp = return "Show a replay token for replaying tests"

-- | The number of successful test cases required before Hedgehog will pass a test
newtype HedgehogTestLimit = HedgehogTestLimit (Maybe TestLimit)
  deriving (Eq, Ord, Show, Typeable)

instance IsOption HedgehogTestLimit where
  defaultValue = HedgehogTestLimit Nothing
  parseValue = fmap (HedgehogTestLimit . Just . TestLimit) . safeRead
  optionName = return "hedgehog-tests"
  optionHelp = return "Number of successful test cases required before Hedgehog will pass a test"

-- | The number of discarded cases allowed before Hedgehog will fail a test
newtype HedgehogDiscardLimit = HedgehogDiscardLimit (Maybe DiscardLimit)
  deriving (Eq, Ord, Show, Typeable)

instance IsOption HedgehogDiscardLimit where
  defaultValue = HedgehogDiscardLimit Nothing
  parseValue = fmap (HedgehogDiscardLimit . Just . DiscardLimit) . safeRead
  optionName = return "hedgehog-discards"
  optionHelp = return "Number of discarded cases allowed before Hedgehog will fail a test"

-- | The number of shrinks allowed before Hedgehog will fail a test
newtype HedgehogShrinkLimit = HedgehogShrinkLimit (Maybe ShrinkLimit)
  deriving (Eq, Ord, Show, Typeable)

instance IsOption HedgehogShrinkLimit where
  defaultValue = HedgehogShrinkLimit Nothing
  parseValue = fmap (HedgehogShrinkLimit . Just . ShrinkLimit) . safeRead
  optionName = return "hedgehog-shrinks"
  optionHelp = return "Number of shrinks allowed before Hedgehog will fail a test"

-- | The number of times to re-run a test during shrinking
newtype HedgehogShrinkRetries = HedgehogShrinkRetries (Maybe ShrinkRetries)
  deriving (Eq, Ord, Show, Typeable)

instance IsOption HedgehogShrinkRetries where
  defaultValue = HedgehogShrinkRetries Nothing
  parseValue = fmap (HedgehogShrinkRetries . Just . ShrinkRetries) . safeRead
  optionName = return "hedgehog-retries"
  optionHelp = return "Number of times to re-run a test during shrinking"

-- | Whether to use colored output or not
newtype HedgehogUseColor = HedgehogUseColor UseColor
  deriving (Eq, Ord, Show, Typeable)

instance IsOption HedgehogUseColor where 
  defaultValue = HedgehogUseColor DisableColor
  parseValue "DisableColor" = Just (HedgehogUseColor DisableColor)
  parseValue "EnableColor" = Just (HedgehogUseColor EnableColor)
  parseValue _ = Nothing
  optionName = return "hedgehog-use-color"
  optionHelp = return "Whether to use colored output or not"

propertyTestLimit :: PropertyConfig -> TestLimit
propertyTestLimit =
  let
    getTestLimit (EarlyTermination _ tests) = tests
    getTestLimit (NoEarlyTermination _ tests) = tests
    getTestLimit (NoConfidenceTermination tests) = tests
  in
    getTestLimit . propertyTerminationCriteria

reportToProgress :: PropertyConfig
                 -> Report Progress
                 -> T.Progress
reportToProgress config (Report testsDone _ _ status) =
  let
    TestLimit testLimit = propertyTestLimit config
    ShrinkLimit shrinkLimit = propertyShrinkLimit config
    ratio x y = 1.0 * fromIntegral x / fromIntegral y
  in
    -- TODO add details for tests run / discarded / shrunk
    case status of
      Running ->
        T.Progress "Running" (ratio testsDone testLimit)
      Shrinking fr ->
        T.Progress "Shrinking" (ratio (failureShrinks fr) shrinkLimit)

reportOutput :: Bool
             -> PropertyName
             -> UseColor
             -> Report Result
             -> IO String
reportOutput showReplay name useColor report = do
  s <- renderResult useColor (Just name) report
  pure $ case reportStatus report of
    Failed fr ->
      let
        size = failureSize fr
        seed = failureSeed fr
        replayStr =
          if showReplay
          then
            "\nUse '--hedgehog-replay \"" ++
            show size ++ " " ++ show seed ++
            "\"' to reproduce."
          else ""
      in
        s ++ replayStr ++ "\n"
    _ -> s

instance T.IsTest HP where
  testOptions =
    return [ Option (Proxy :: Proxy HedgehogReplay)
           , Option (Proxy :: Proxy HedgehogShowReplay)
           , Option (Proxy :: Proxy HedgehogTestLimit)
           , Option (Proxy :: Proxy HedgehogDiscardLimit)
           , Option (Proxy :: Proxy HedgehogShrinkLimit)
           , Option (Proxy :: Proxy HedgehogShrinkRetries)
           , Option (Proxy :: Proxy HedgehogUseColor)
           ]

  run opts (HP propName (Property pConfig pTest)) yieldProgress = do
    let
      HedgehogReplay         replay = lookupOption opts
      HedgehogShowReplay showReplay = lookupOption opts
      HedgehogTestLimit       mTests = lookupOption opts
      HedgehogDiscardLimit mDiscards = lookupOption opts
      HedgehogShrinkLimit   mShrinks = lookupOption opts
      HedgehogShrinkRetries mRetries = lookupOption opts
      HedgehogUseColor useColor = lookupOption opts
      config =
        PropertyConfig
          (fromMaybe (propertyDiscardLimit pConfig) mDiscards)
          (fromMaybe (propertyShrinkLimit pConfig) mShrinks)
          (fromMaybe (propertyShrinkRetries pConfig) mRetries)
          (NoConfidenceTermination $ fromMaybe (propertyTestLimit pConfig) mTests)

    randSeed <- Seed.random
    let
      size = maybe 0 fst replay
      seed = maybe randSeed snd replay

    report <- checkReport config size seed pTest (yieldProgress . reportToProgress config)

    let
      resultFn = if reportStatus report == OK
                 then T.testPassed
                 else T.testFailed

    out <- reportOutput showReplay propName useColor report
    return $ resultFn out
