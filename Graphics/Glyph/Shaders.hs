module Graphics.Glyph.Shaders where

import Graphics.Rendering.OpenGL
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import Control.Monad
import Data.Maybe
import Data.List as List
import Graphics.Glyph.Util

{- Load a shader from a file giving the type of the shader
 - to load.
 - This function returns the shader log as a string and
 - a shader as a maybe. Nothing if the shader didn't complie
 - and Just if the shader did compile
 -}
class IsShaderSource a where
    loadShader :: ShaderType -> a -> IO (String, Maybe Shader)

instance IsShaderSource FilePath where
    loadShader typ path = loadShaderBS path typ =<< BS.readFile path

instance IsShaderSource BS.ByteString where
    loadShader = loadShaderBS "Inlined"

instance IsShaderSource BSL.ByteString where
    loadShader typ = loadShader typ . toStrict
        where toStrict = BS.concat . BSL.toChunks

noShader :: Maybe String
noShader = Nothing

loadShaderBS :: String -> ShaderType -> BS.ByteString -> IO (String, Maybe Shader)
loadShaderBS ctx typ src = do
    shader <- createShader typ
    shaderSourceBS shader $= src
    compileShader shader

    ok <- get (compileStatus shader)
    infoLog <- get (shaderInfoLog shader)

    unless ok $
        deleteObjectNames [shader]

    if not ok then
        return ( unlines $ map ((ctx ++ " " ++ show typ ++ ": ")++) $ lines infoLog, Nothing )
        else return ( infoLog, Just shader );


{- Load multiple shaders -}
loadShaders :: (IsShaderSource a) => [(ShaderType,a)] -> IO [(String, Maybe Shader)]
loadShaders = mapM ( uncurry loadShader )

{- Return the sucessfully complied shaders
 - as a new array of working shaders -}
workingShaders :: [(a, Maybe Shader)] -> [Shader]
workingShaders = mapMaybe snd

{- Create a program from a list of working shaders -}
createShaderProgram :: [Shader] -> IO (String, Maybe Program)
createShaderProgram shaders = do
    p <- createProgram
    mapM_ (attachShader p) shaders
    linkProgram p

    ok <- get $ linkStatus p
    info <- get $ programInfoLog p

    unless ok $
        deleteObjectNames [p]

    return ( info, not ok ? Nothing $ Just p )

{- Creates a shader program, but will only build the program if all the
 - shaders compiled correctly -}
createShaderProgramSafe :: [(String,Maybe Shader)] -> IO (String, Maybe Program)
createShaderProgramSafe shaders = 
    not (List.all (isJust.snd) shaders) ?
        return (concatMap fst shaders, Nothing) $
        createShaderProgram $ workingShaders shaders
        

getUniformLocationsSafe :: Program -> [String] -> IO [ Maybe UniformLocation ]
getUniformLocationsSafe prog uniforms =
    forM uniforms $ \uniform -> do
        tmp <- get $ uniformLocation prog uniform
        case tmp of
            UniformLocation (-1) -> return $ Nothing
            _ ->  return $Just tmp

loadProgramFullSafe ::
    (IsShaderSource tc,
     IsShaderSource te,
     IsShaderSource g,
     IsShaderSource v,
     IsShaderSource f) => Maybe (tc,te) -> Maybe g -> v -> f -> IO (Maybe Program)
loadProgramFullSafe tess geometry vert frag = do
    let (ts1,ts2) = distribMaybe tess
    shaders <- sequence $ catMaybes [
            Just $ loadShader VertexShader vert,
            Just $ loadShader FragmentShader frag,
            liftM (loadShader GeometryShader) geometry,
            liftM (loadShader TessControlShader) ts1,
            liftM (loadShader TessEvaluationShader) ts2]
    (linklog,maybeProg) <- createShaderProgramSafe shaders
    if isNothing maybeProg then do
        putStrLn "Failed to link program"
        putStrLn linklog
        return Nothing
        else return maybeProg


loadProgramSafe ::
    (IsShaderSource a,
     IsShaderSource b,
     IsShaderSource c) =>
        a -> b -> Maybe c -> IO (Maybe Program)
loadProgramSafe vert frag geom = loadProgramFullSafe (Nothing::Maybe(String,String)) geom vert frag
