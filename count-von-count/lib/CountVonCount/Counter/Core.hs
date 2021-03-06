--------------------------------------------------------------------------------
-- | This module implements the counter logic for a /single/ team
{-# LANGUAGE DeriveDataTypeable #-}
module CountVonCount.Counter.Core
    ( CounterCoreEvent (..)
    , isLapEvent
    , CounterState (..)
    , emptyCounterState
    , counterLastUpdate
    , CounterM
    , runCounterM
    , stepCounterState
    ) where


--------------------------------------------------------------------------------
import           Control.Monad.State          (State, get, put, runState)
import           Control.Monad.Writer         (WriterT, runWriterT, tell)
import           Data.Foldable                (forM_)
import           Data.List                    (minimumBy)
import           Data.Ord                     (comparing)
import           Data.Time                    (UTCTime, diffUTCTime)
import           Data.Typeable                (Typeable)
import           Text.Printf                  (printf)


--------------------------------------------------------------------------------
import           CountVonCount.Counter.Modulo
import           CountVonCount.Persistence    (Station (..))
import           CountVonCount.Sensor.Filter


--------------------------------------------------------------------------------
data CounterCoreEvent
    = PositionCoreEvent UTCTime Station Double
    -- ^ The position of a team is set to the given station at the given time
    --   with a speed estimate.
    | LapCoreEvent UTCTime Double [Station]
    -- ^ A team has completed a lap at the given time with the given round
    --   time and missed the given stations.
    deriving (Show)


--------------------------------------------------------------------------------
isLapEvent :: CounterCoreEvent -> Bool
isLapEvent LapCoreEvent{} = True
isLapEvent _              = False


--------------------------------------------------------------------------------
data CounterState
    -- | No data for now
    = NoCounterState
    -- | lap start, previous event, missed stations, current speed, last seen
    | CounterState SensorEvent SensorEvent [Station] Double UTCTime
    deriving (Show, Typeable)


--------------------------------------------------------------------------------
emptyCounterState :: CounterState
emptyCounterState = NoCounterState


--------------------------------------------------------------------------------
counterLastUpdate :: CounterState -> Maybe UTCTime
counterLastUpdate NoCounterState           = Nothing
counterLastUpdate (CounterState _ _ _ _ t) = Just t


--------------------------------------------------------------------------------
type CounterM a = WriterT [String] (State CounterState) a


--------------------------------------------------------------------------------
runCounterM :: CounterM a -> CounterState -> (a, [String], CounterState)
runCounterM c cs =
    let state             = runWriterT c
        ((x, tells), cs') = runState state cs
    in (x, tells, cs')


--------------------------------------------------------------------------------
tell' :: String -> CounterM ()
tell' x = tell [x]




--------------------------------------------------------------------------------
stepCounterState :: Double                       -- ^ Length of the circuit
                 -> Double                       -- ^ Absolute maximum speed
                 -> [Station]                    -- ^ Detection stations
                 -> SensorEvent                  -- ^ Incoming event
                 -> CounterM [CounterCoreEvent]  -- ^ Outgoing events
stepCounterState len maxSpeed stations event = do
    state <- get
    case state of
        NoCounterState               -> do
            put $ CounterState event event [] 0 (sensorTime event)
            let position = stationPosition $ sensorStation event
            tell' $ printf ("Initialized counter state (%.2fm), " ++
                            "next lap time could be incorrect for this team")
                            position
            return []
        CounterState lapStart prev prevMissed prevSpeed _
            -- At the same station, just update the time.
            | station == prevStation -> do
                put $ CounterState lapStart prev prevMissed prevSpeed time
                return []
            -- Refused sensor event
            | null possibilities     -> do
                tell' $ "Impossibru@" ++ show curStationName
                return []
            | otherwise              -> do
                forM_ missed $ \s -> tell' $ printf "Missed station " ++ show s
                tell' $ printf "New position: %.2fm (last: %.2fm, %0fs ago)"
                            position prevPosition dt
                tell' $ printf "Most likely: moved %.2fm at %.2fm/s" dx speed
                tell' $ printf "Updated average speed from %.2fm/s to %.2fm/s"
                            prevSpeed speed'
                if numLaps > 0
                  then do tell' $ printf "Adding %d laps (lap time: %.2fs)"
                                      numLaps lapTime
                          put $ CounterState event event [] speed' time
                  else put $ CounterState lapStart event allMissed speed' time
                return $
                    replicate numLaps (LapCoreEvent time lapTime allMissed) -- 0 or 1 times
                    ++ [PositionCoreEvent time station speed]
          where
            SensorEvent lapStartTime       _ _ _ _ = lapStart
            SensorEvent time     station     _ _ _ = event
            SensorEvent prevTime prevStation _ _ _ = prev

            Station _ curStationName _ position    = station
            Station _ _ _ prevPosition             = prevStation

            dt            = time `diffTime` prevTime
            possibilities = solve len maxSpeed prevPosition position dt

            -- Which stations we have missed (hopfully none)
            missed        = takeWhile (station /= )    $
                            tail                       $
                            dropWhile (prevStation /=) $
                            cycle stations

            allMissed   = missed ++ prevMissed

            -- Pick the (dx, speed) so that speed close to the previously
            -- known speed
            {-
            (dx, speed) = minimumBy
                (comparing $ \(_, sp) -> abs (sp - prevSpeed))
                possibilities
            -}
            -- This allows a team to take a nap and score some extra points in
            -- the meanwhile. Hence, we just take the minimum speed for noew.
            (dx, speed) = minimumBy (comparing snd) possibilities

            -- Update exponentially moving average
            speed' = prevSpeed * 0.7 + speed * 0.3

            -- Calculate number of laps to emit (usually 0)
            numLaps :: Int
            numLaps = floor $ (prevPosition + dx) / len

            -- Time between the current event and the start of the lap
            lapTime :: Double
            lapTime = (time `diffTime` lapStartTime) / toEnum numLaps

            diffTime t1 t2 = fromRational $ toRational $ t1 `diffUTCTime` t2


--------------------------------------------------------------------------------
solve :: Double              -- ^ Length of the circuit
      -> Double              -- ^ Absolute maximum speed
      -> Double              -- ^ Previous position
      -> Double              -- ^ Current position
      -> Double              -- ^ Delta time
      -> [(Double, Double)]  -- ^ Possible (delta position, speed) values
solve len max' x1 x2 dt = takeWhile ((< max') . snd)
    [(dx, sp) | dx <- dxs, let sp = dx / dt, sp > 0]
  where
    dxs = fromModulo (toModulo x2 .-. toModulo x1) len
