module Handler.Class where

import           Import
import qualified Text.Blaze   as TB
import           DB
import qualified Auth.Account as Auth

-- import qualified Util as Util
-- import qualified Data.ByteString as S
-- import qualified Data.ByteString.Lazy as L
-- import Data.Conduit.Binary

-- import Yesod.Form.MassInput
import Yesod.Form.Bootstrap3 (BootstrapFormLayout (..), renderBootstrap3)
-- import Yesod.Form.Jquery (jqueryAutocompleteField)

--------------------------------------------------------------------------------
-- | Viewing Existing Classes --------------------------------------------------
--------------------------------------------------------------------------------
getClassInsR :: ClassId -> Handler Html
getClassInsR classId = do
  klass                 <- getClassById classId
  instr                 <- getUserById (classInstructor klass)
  asgns                 <- getAssignmentsByClass classId
  students              <- getStudentsByClass    classId
  teachers              <- fmap entityVal <$> getInstructorsByClass classId
  let instructors        = instr : teachers
  (asgnWidget, asgnEnc) <- generateFormPost newAssignForm
  (stdWidget,  stdEnc)  <- generateFormPost addUserForm
  (insWidget,  insEnc)  <- generateFormPost addUserForm
  defaultLayout $
    $(widgetFile "viewClassInstructor")

getClassStdR :: ClassId -> Handler Html
getClassStdR _ = do
  setMessage "TODO: getClassStdR: HEREHEREHEREHERE"
  defaultLayout $
    $(widgetFile "viewClassStudent")

getAssignmentR :: ClassId -> AssignmentId -> Handler Html
getAssignmentR classId assignId = do
  klass               <- getClassById classId
  instr               <- getUserById  (classInstructor klass)
  asgn                <- getAssignmentById assignId
  scores              <- getAssignmentScores classId assignId
  (stdWidget, stdEnc) <- generateFormPost (scoreForm scores)
  defaultLayout $
    $(widgetFile "viewassignment")

--------------------------------------------------------------------------------
-- | Update Scores for Assignment ----------------------------------------------
--------------------------------------------------------------------------------
postScoreR :: ClassId -> AssignmentId -> Handler Html
postScoreR classId assignId = do
  oldScores <- getAssignmentScores classId assignId
  extendClassFormR
    "update scores"
    (scoreForm oldScores)
    (updAssignmentScores assignId . updScores oldScores)
    classId
    (AssignmentR classId assignId)

--------------------------------------------------------------------------------
-- | Adding New Instructors ----------------------------------------------------
--------------------------------------------------------------------------------
postNewInstructorR :: ClassId -> Handler Html
postNewInstructorR classId =
  extendClassFormR
    "add instructor"
    addUserForm
    (addInstructorR classId)
    classId
    (ClassInsR classId)

addInstructorR :: ClassId -> AddUserForm -> Handler ()
addInstructorR classId userForm = do
  mbStd <- addUserR classId userForm
  case mbStd of
    Nothing ->    setMessage $ "Error adding instructor: " ++ TB.text (auEmail userForm)
    Just e  -> do setMessage $ "Added instructor: "        ++ TB.text (auEmail userForm)
                  void $ runDB (insert (Teacher (entityKey e) classId))

--------------------------------------------------------------------------------
-- | Creating New Assignments --------------------------------------------------
--------------------------------------------------------------------------------
postNewAssignR :: ClassId -> Handler Html
postNewAssignR classId =
  extendClassFormR
    "create assignment"
    newAssignForm
    (addAssignR classId)
    classId
    (ClassInsR classId)

addAssignR :: ClassId -> NewAssignForm -> Handler ()
addAssignR classId (NewAssignForm aName aPts) = do
  _ <- runDB $ insert $ Assignment aName aPts classId
  setMessage $ "Added new assignment: " ++ TB.text aName

scoreForm :: [(Entity User, Int)] -> Form [(Text, Int)]
scoreForm scores = renderBootstrap3 BootstrapBasicForm
                     $ sequenceA $ map userForm scores
  where
    userForm (user, score) = (,) <$> pure email
                                 <*> areq intField (textString email) (Just score)
      where
        email = userEmailAddress (entityVal user)

textString :: (IsString a) => Text -> a
textString = fromString . unpack

dummyScores :: [(Text, Int)]
dummyScores = [ ("Michael", 26)
              , ("Alice"  , 10)
              , ("Robert" , 19)
              ]

data NewAssignForm = NewAssignForm
  { asgnName   :: Text
  , asgnPoints :: Int
  }
  deriving (Show)

newAssignForm :: Form NewAssignForm
newAssignForm = renderBootstrap3 BootstrapBasicForm $ NewAssignForm
  <$> areq textField "Name"   Nothing -- (Just "e.g. HW 1")
  <*> areq intField  "Points" Nothing -- (Just 10)

--------------------------------------------------------------------------------
-- | Enrolling New Students ----------------------------------------------------
--------------------------------------------------------------------------------
data AddUserForm = AddUserForm
  { auEmail :: Text }
  deriving (Show)

addUserForm :: Form AddUserForm
addUserForm = renderBootstrap3 BootstrapBasicForm $ AddUserForm
  <$> areq textField "Email" Nothing

postNewStudentR :: ClassId -> Handler Html
postNewStudentR classId =
  extendClassFormR
    "enroll student"
    addUserForm
    (addStudentR classId)
    classId
    (ClassInsR classId)

addStudentR :: ClassId -> AddUserForm -> Handler ()
addStudentR classId userForm = do
  mbStd <- addUserR classId userForm
  case mbStd of
    Nothing ->    setMessage $ "Error enrolling student: " ++ TB.text (auEmail userForm)
    Just e  -> do setMessage $ "Enrolled student: "        ++ TB.text (auEmail userForm)
                  void $ runDB (insert (Student (entityKey e) classId))

addUserR :: ClassId -> AddUserForm -> Handler (Maybe (Entity User))
addUserR classId (AddUserForm sEmail) = do
  mbU <- getUserByEmail sEmail
  case mbU of
    Just _  -> return mbU
    Nothing -> do _ <- Auth.createNewCustomAccount
                         (Auth.CustomNewAccountData sEmail ("?" ++ sEmail ++ "?") sEmail sEmail)
                         (const (ClassInsR classId))
                  getUserByEmail sEmail

--------------------------------------------------------------------------------
-- | Generic Class Extension ---------------------------------------------------
--------------------------------------------------------------------------------
extendClassFormR
  :: Html -> Form a -> (a -> Handler ()) -> ClassId -> Route App -> Handler Html
extendClassFormR msg form extR classId r = do
  instrId      <- classInstructor <$> getClassById classId
  (uid    , _) <- requireAuthPair
  if uid /= instrId
    then setMessage ("Sorry, can only " ++ msg ++ "for your own class!")
    else do
      ((result, _), _) <- runFormPost form
      case result of
        FormSuccess o -> extR o
        _             -> setMessage "Something went wrong!"
  redirect r

--------------------------------------------------------------------------------
-- | Creating New Classes ------------------------------------------------------
--------------------------------------------------------------------------------
data NewClassForm = NewClassForm
    { name       :: Text
    , term       :: Text
    }
    deriving (Show)

postNewClassR :: Handler Html
postNewClassR = do
  (uid    , _)     <- requireAuthPair
  ((result, _), _) <- runFormPost newClassForm
  case result of
    FormSuccess (NewClassForm cName cTerm) -> do
      _ <- runDB $ insert $ Class cName cTerm uid
      setMessage $ "Added new class! " ++ TB.text cName ++ " in term " ++ TB.text cTerm
      redirect ProfileR
    _ -> do
      setMessage "Yikes! Something went wrong"
      redirect NewClassR

getNewClassR :: Handler Html
getNewClassR = do
  (formWidget, formEnctype) <- generateFormPost newClassForm
  defaultLayout $
    $(widgetFile "newclass")

newClassForm :: Form NewClassForm
newClassForm = renderBootstrap3 BootstrapBasicForm $ NewClassForm
    <$> areq textField "Name" Nothing -- (Just "CSE 130: Programming Languages")
    <*> areq textField "Term" Nothing -- (Just "Fall 2017")
