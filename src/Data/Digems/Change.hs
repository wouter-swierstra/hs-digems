{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE GADTs                 #-}
module Data.Digems.Change where

import           Control.Monad.Cont
import           Control.Monad.State
import           Data.Functor.Const
import qualified Data.Map as M
import qualified Data.Set as S
import           Data.List (nub, sortBy)
import           Data.Type.Equality
----------------------------------------
import           Generics.MRSOP.Util
import           Generics.MRSOP.Base
----------------------------------------
import           Data.Exists
import           Data.Digems.MetaVar
import           Generics.MRSOP.Digems.Treefix

-- |A 'CChange', or, closed change, consists in a declaration of metavariables
--  and two contexts. The precondition is that every variable declared
--  occurs at least once in ctxDel and that every variable that occurs in ctxIns
--  is declared.
--  
data CChange ki codes at where
  CMatch :: { cCtxVars :: S.Set (Exists (MetaVarIK ki))
            , cCtxDel  :: UTx ki codes (MetaVarIK ki) at 
            , cCtxIns  :: UTx ki codes (MetaVarIK ki) at }
         -> CChange ki codes at

-- |smart constructor for 'CChange'. Enforces the invariant
cmatch :: UTx ki codes (MetaVarIK ki) at -> UTx ki codes (MetaVarIK ki) at
       -> CChange ki codes at
cmatch del ins =
  let vi = utxGetHolesWith Exists ins
      vd = utxGetHolesWith Exists del
   in if vi == vd
      then CMatch vi del ins
      else error "Data.Digems.Change.cmatch: invariant failure"

-- |Returns the maximum variable in a change
cMaxVar :: CChange ki codes at -> Int
cMaxVar = maybe 0 id . S.lookupMax . S.map (exElim metavarGet) . cCtxVars

instance (Show1 ki) => Show (CChange ki codes at) where
  show (CMatch _ del ins)
    = "{- " ++ show1 del ++ " -+ " ++ show1 ins ++ " +}"

instance HasIKProjInj ki (CChange ki codes) where
  konInj k = CMatch S.empty (UTxOpq k) (UTxOpq k)
  varProj pk (CMatch _ (UTxHole h) _)   = varProj pk h
  varProj _  (CMatch _ (UTxPeel _ _) _) = Just IsI
  varProj _  (CMatch _ _ _)             = Nothing

instance (TestEquality ki) => TestEquality (CChange ki codes) where
  testEquality (CMatch _ x _) (CMatch _ y _)
    = testEquality x y

-- |Alpha-equality for 'CChange'
changeEq :: (Eq1 ki) => CChange ki codes at -> CChange ki codes at -> Bool
changeEq (CMatch v1 d1 i1) (CMatch v2 d2 i2)
  = S.size v1 == S.size v2 && aux
 where
   aux :: Bool
   aux = (`runCont` id) $
     callCC $ \exit -> flip evalStateT M.empty $ do
       _ <- utxMapM (uncurry' (reg (cast exit))) (utxLCP d1 d2)
       _ <- utxMapM (uncurry' (chk (cast exit))) (utxLCP i1 i2)
       return True
   
   cast :: (Bool -> Cont Bool b)
        -> Bool -> Cont Bool (Const () a)
   cast f b = (const (Const ())) <$> f b

   reg :: (Bool -> Cont Bool (Const () at))
       -> UTx ki codes (MetaVarIK ki) at
       -> UTx ki codes (MetaVarIK ki) at
       -> StateT (M.Map Int Int) (Cont Bool) (Const () at)
   reg _ (UTxHole m1) (UTxHole m2) 
     = modify (M.insert (metavarGet m1) (metavarGet m2))
     >> return (Const ())
   reg exit _ _ 
     = lift $ exit False

   chk :: (Bool -> Cont Bool (Const () at))
       -> UTx ki codes (MetaVarIK ki) at
       -> UTx ki codes (MetaVarIK ki) at
       -> StateT (M.Map Int Int) (Cont Bool) (Const () at)
   chk exit (UTxHole m1) (UTxHole m2) 
     = do st <- get
          case M.lookup (metavarGet m1) st of
            Nothing -> lift $ exit False
            Just r  -> if r == metavarGet m2
                       then return (Const ())
                       else lift $ exit False
   chk exit _ _ = lift (exit False)

-- |Issues a copy, this is a closed change analogous to
--  > \x -> x
changeCopy :: MetaVarIK ki at -> CChange ki codes at
changeCopy vik = CMatch (S.singleton (Exists vik)) (UTxHole vik) (UTxHole vik)

-- |Checks whetehr a change is a copy.
isCpy :: (Eq1 ki) => CChange ki codes at -> Bool
isCpy (CMatch _ (UTxHole v1) (UTxHole v2))
  -- arguably, we don't even need that since changes are closed.
  = metavarGet v1 == metavarGet v2
isCpy _ = False

makeCopyFrom :: CChange ki codes at -> CChange ki codes at
makeCopyFrom chg = case cCtxDel chg of
  UTxHole var -> changeCopy var
  UTxPeel _ _ -> changeCopy (NA_I (Const 0))
  UTxOpq k    -> changeCopy (NA_K (Annotate 0 k))
  
{-
-- |Renames all changes within a 'UTx' so that their
--  variable names will not clash.
alphaRenameChanges :: UTx ki codes (CChange ki codes) at
                   -> UTx ki codes (CChange ki codes) at
alphaRenameChanges = flip evalState 0 . utxMapM rename1                   
  where
    rename1 :: CChange ki codes at -> State Int (CChange ki codes at)
    rename1 (CMatch vars del ins) =
      let localMax = (1+) . maybe 0 id . S.lookupMax $ S.map (exElim metavarGet) vars
       in do globalMax <- get
             put (globalMax + localMax)
             return (CMatch (S.map (exMap (metavarAdd localMax)) vars)
                            (utxMap (metavarAdd localMax) del)
                            (utxMap (metavarAdd localMax) ins))
-}

-- |A Utx with closed changes distributes over a closed change
--
distrCChange :: UTx ki codes (CChange ki codes) at -> CChange ki codes at
distrCChange = naiveDistr -- . alphaRenameChanges    
  where
    naiveDistr utx =
      let vars = S.foldl' S.union S.empty
               $ utxGetHolesWith cCtxVars utx
          del  = utxJoin $ utxMap cCtxDel utx
          ins  = utxJoin $ utxMap cCtxIns utx
       in CMatch vars del ins

-- |A 'OChange', or, open change, is analogous to a 'CChange',
--  but has a list of free variables. These are the ones that appear
--  in 'oCtxIns' but not in 'oCtxDel'
data OChange ki codes at where
  OMatch :: { oCtxVDel :: S.Set (Exists (MetaVarIK ki))
            , oCtxVIns :: S.Set (Exists (MetaVarIK ki))
            , oCtxDel  :: UTx ki codes (MetaVarIK ki) at 
            , oCtxIns  :: UTx ki codes (MetaVarIK ki) at }
         -> OChange ki codes at
