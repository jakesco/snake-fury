{-# LANGUAGE TypeApplications #-}

{-|
This module handle the external events of the game. That is: the user inputs and the time. 
-}
module EventQueue where

import qualified GameState as Snake
import Control.Concurrent
    ( MVar, readMVar, swapMVar )
import Control.Concurrent.BoundedChan
    ( BoundedChan, tryWriteChan, tryReadChan )
import System.IO (hReady, stdin)
import GameState (Movement(..))


-- | The are two kind of events, a `ClockEvent`, representing movement which is not force by the user input, and `UserEvent` which is the opposite.
data Event = Tick | UserEvent Snake.Movement

-- | the `UserInputQueue` is an asynchronous bounded channel which contains snake movements. This channel is feeded by key strokes
type UserInputQueue = BoundedChan Snake.Movement

-- | The `EventQueue` has a `UserInputQueue` and the global speed of consumption (as a mutable reference) and the initial speed of the game.
data EventQueue = EventQueue {userInput :: UserInputQueue, currentSpeed :: MVar Int, initialSpeed :: Int}

-- | Given the current score, updates the global shared speed every 10 points by a factor of 10%. Returns the current state
calculateSpeed :: Int -> Int -> Int
calculateSpeed score initialSpeed =
    let level = min score 50 `quot` 10              -- maximun of 5 levels every 10 apples
        speedFactor = 1 - fromIntegral level / 10.0 -- every level speeds up the time by a 10%
     in floor @Double $ fromIntegral initialSpeed * speedFactor

-- | Given the current score and the event queue, updates the new speed and returns it. 
--   This action is mutable, therefore must be run in the IO mondad
setSpeed :: Int -> EventQueue -> IO Int
setSpeed s (EventQueue _ m_current initial_speed) = do
  current_speed <- readMVar m_current   -- Read the current 
  if new_speed == current_speed
    then return current_speed
    else swapMVar m_current new_speed >> return new_speed
 where new_speed = calculateSpeed s initial_speed

-- |---------------|
-- |- User Inputs -|
-- |---------------|

-- In StackOverflow we trust.
getKey :: IO [Char]
getKey = reverse <$> getKey' ""
  where getKey' chars = do
          char <- getChar
          more <- hReady stdin
          (if more then getKey' else return) (char:chars)

-- | This function translate key strokes to movements and push then into the queue. 
-- The player is free to push keys as fast a he/she can but the userqueue is bounded,
-- meaning that if we push a movement to a filled queue it gets discarded.
-- This is intented for the game play, If we press keys faster than the game speed
-- they will be enqueued and pushed into the game with delay. 
writeUserInput :: EventQueue -> IO ()
writeUserInput queue@(EventQueue userqueue _ _) = do
    c <- getKey
    case c of
      "\ESC[A" -> tryWriteChan userqueue North >> writeUserInput queue -- \ESC[A/D/C/B are the escape codes for the arrow keys.
      "\ESC[D" -> tryWriteChan userqueue West  >> writeUserInput queue
      "\ESC[C" -> tryWriteChan userqueue East  >> writeUserInput queue
      "\ESC[B" -> tryWriteChan userqueue South >> writeUserInput queue
      _   -> writeUserInput queue

-- | Read the EventQueue and generates an Event to pass to the user logic
readEvent :: EventQueue -> IO Event
readEvent (EventQueue userqueue _ _) = do
  mv <- tryReadChan userqueue
  case mv of
    Nothing -> pure Tick
    Just move -> return $ UserEvent move