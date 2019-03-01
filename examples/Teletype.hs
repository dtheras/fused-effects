{-# LANGUAGE DeriveFunctor, FlexibleContexts, FlexibleInstances, GeneralizedNewtypeDeriving, KindSignatures, LambdaCase, MultiParamTypeClasses, TypeOperators, UndecidableInstances #-}

module Teletype where

import Prelude hiding (read)

import Control.Effect
import Control.Effect.Carrier
import Control.Effect.State
import Control.Effect.Sum
import Control.Effect.Writer
import Control.Monad.IO.Class
import Data.Coerce
import Test.Hspec
import Test.Hspec.QuickCheck

spec :: Spec
spec = describe "teletype" $ do
  prop "reads" $
    \ line -> run (runTeletypeRet [line] read) `shouldBe` ([], ([], line))

  prop "writes" $
    \ input output -> run (runTeletypeRet input (write output)) `shouldBe` ([output], (input, ()))

  prop "writes multiple things" $
    \ input output1 output2 -> run (runTeletypeRet input (write output1 >> write output2)) `shouldBe` ([output1, output2], (input, ()))

data Teletype (m :: * -> *) k
  = Read (String -> k)
  | Write String k
  deriving (Functor)

instance HFunctor Teletype where
  hmap _ = coerce
  {-# INLINE hmap #-}

instance Effect Teletype where
  handle state handler (Read    k) = Read (handler . (<$ state) . k)
  handle state handler (Write s k) = Write s (handler (k <$ state))

read :: (Member Teletype sig, Carrier sig m) => m String
read = send (Read pure)

write :: (Member Teletype sig, Carrier sig m) => String -> m ()
write s = send (Write s (pure ()))


runTeletypeIO :: TeletypeIOC m a -> m a
runTeletypeIO = runTeletypeIOC

newtype TeletypeIOC m a = TeletypeIOC { runTeletypeIOC :: m a }
  deriving (Applicative, Functor, Monad, MonadIO)

instance (MonadIO m, Carrier sig m) => Carrier (Teletype :+: sig) (TeletypeIOC m) where
  eff = handleSum (TeletypeIOC . eff . handleCoercible) (\case
    Read    k -> liftIO getLine      >>= k
    Write s k -> liftIO (putStrLn s) >>  k)


runTeletypeRet :: Functor m => [String] -> TeletypeRetC m a -> m ([String], ([String], a))
runTeletypeRet i = runWriter . runState i . runTeletypeRetC

newtype TeletypeRetC m a = TeletypeRetC { runTeletypeRetC :: StateC [String] (WriterC [String] m) a }
  deriving (Applicative, Functor, Monad)

instance (Carrier sig m, Effect sig) => Carrier (Teletype :+: sig) (TeletypeRetC m) where
  eff = TeletypeRetC . handleSum (eff . R . R . handleCoercible) (\case
    Read k -> do
      i <- get
      case i of
        []  -> runTeletypeRetC (k "")
        h:t -> put t *> runTeletypeRetC (k h)
    Write s k -> tell [s] *> runTeletypeRetC k)
