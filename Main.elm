module Main exposing (main)

import Dict
import Html exposing (Html, div, text)
import Html.Attributes exposing (style)
import Keyboard
import Random
import RasterShapes as Raster exposing (Position, Size)
import Set exposing (Set)
import Time
import Piece exposing (..)


numCols : Int
numCols =
    10


numRows : Int
numRows =
    20



-- XXX current speed


type alias State =
    { currentScore : Int
    , currentPiece : Piece
    , currentPiecePosition : ( Int, Int )
    , nextPiece : Piece
    , fixatedBlocks : Set ( Int, Int )
    , dropping : Bool
    }


type Model
    = Uninitialized
    | Initialized State
    | GameOver Int
    | Error String


init : ( Model, Cmd Msg )
init =
    ( Uninitialized, Random.generate (uncurry Initialize) <| Random.pair pieceGenerator pieceGenerator )


type Msg
    = Initialize Piece Piece
    | NextPiece Piece
    | Tick
    | MoveLeft
    | MoveRight
    | Drop
    | StopDrop
    | Rotate
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case model of
        GameOver _ ->
            ( model, Cmd.none )

        Uninitialized ->
            case msg of
                Initialize currentPiece nextPiece ->
                    let
                        newModel =
                            Initialized
                                { currentScore = 0
                                , currentPiece = currentPiece
                                , currentPiecePosition = ( 0, 0 )
                                , nextPiece = nextPiece
                                , fixatedBlocks = Set.empty
                                , dropping = False
                                }
                    in
                        ( newModel, Cmd.none )

                _ ->
                    ( Error ("Somehow you managed to get a " ++ toString msg ++ " msg in an uninitialized state o_O"), Cmd.none )

        Initialized state ->
            case msg of
                Initialize _ _ ->
                    ( Error "Somehow you managed to get an initialize msg in an initialized state o_O", Cmd.none )

                NoOp ->
                    ( model, Cmd.none )

                MoveLeft ->
                    ( Initialized <| moveCurrentPieceLeft state, Cmd.none )

                MoveRight ->
                    ( Initialized <| moveCurrentPieceRight state, Cmd.none )

                Rotate ->
                    ( Initialized <| rotateCurrentPiece state, Cmd.none )

                Tick ->
                    let
                        newState =
                            movePieceDown state
                    in
                        if detectCollisions newState then
                            ( fixateAndAdvance state, Random.generate NextPiece pieceGenerator )
                        else
                            ( Initialized newState, Cmd.none )

                Drop ->
                    ( Initialized { state | dropping = True }, Cmd.none )

                StopDrop ->
                    ( Initialized { state | dropping = False }, Cmd.none )

                NextPiece piece ->
                    ( Initialized { state | nextPiece = piece }, Cmd.none )

        Error _ ->
            ( model, Cmd.none )


view : Model -> Html Msg
view model =
    case model of
        GameOver score ->
            text <| "Game over! Your score was " ++ toString score

        Uninitialized ->
            text ""

        Initialized state ->
            div []
                [ renderOutline
                    |> pxSize 1
                , renderBoard state.currentPiece state.currentPiecePosition (Set.toList state.fixatedBlocks)
                    |> pxSize 20
                , renderNext state.nextPiece
                    |> pxSize 20
                , pixelWithItems 1 (Position 240 110) [ text (toString state.currentScore) ]
                ]

        Error error ->
            div [] [ text error ]


main : Program Never Model Msg
main =
    Html.program
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


pxSize : Int -> List Position -> Html Msg
pxSize size items =
    items
        |> List.map (pixel size)
        |> div []


anyFixated : State -> Int -> Bool
anyFixated state offset =
    let
        blocks =
            getBlocks state.currentPiece

        ( cx, cy ) =
            state.currentPiecePosition

        newBlocks =
            List.map (\( x, y ) -> ( x + offset + cx, y + cy )) blocks

        blockIsFixated pos =
            Set.member pos state.fixatedBlocks
    in
        List.any blockIsFixated newBlocks


moveCurrentPieceLeft : State -> State
moveCurrentPieceLeft model =
    let
        ( x, y ) =
            model.currentPiecePosition

        left =
            getLeftOffset model.currentPiece
    in
        if x + left <= 0 then
            model
        else if anyFixated model -1 then
            model
        else
            { model | currentPiecePosition = ( x - 1, y ) }


moveCurrentPieceRight : State -> State
moveCurrentPieceRight model =
    let
        ( x, y ) =
            model.currentPiecePosition

        right =
            getRightOffset model.currentPiece
    in
        if x + 4 - right >= numCols then
            model
        else if anyFixated model 1 then
            model
        else
            { model | currentPiecePosition = ( x + 1, y ) }


rotateCurrentPiece : State -> State
rotateCurrentPiece model =
    let
        ( x, y ) =
            model.currentPiecePosition

        newPiece =
            rotate model.currentPiece
    in
        case getRight newPiece of
            Just right ->
                if x + right > numCols then
                    { model | currentPiece = newPiece, currentPiecePosition = ( numCols - right - 1, y ) }
                else
                    { model | currentPiece = newPiece }

            Nothing ->
                Debug.crash "invalid right position!"


movePieceDown : State -> State
movePieceDown state =
    let
        ( x, y ) =
            state.currentPiecePosition
    in
        { state | currentPiecePosition = ( x, y + 1 ) }


translateRelativeTo : ( Int, Int ) -> ( Int, Int ) -> ( Int, Int )
translateRelativeTo ( dx, dy ) ( x, y ) =
    ( dx + x, dy + y )


detectCollisions : State -> Bool
detectCollisions state =
    let
        pieceBlocks =
            List.map (translateRelativeTo state.currentPiecePosition) <| getBlocks state.currentPiece
    in
        List.any (\( _, y ) -> y >= numRows) pieceBlocks || List.any (\point -> Set.member point state.fixatedBlocks) pieceBlocks


fixate : State -> State
fixate state =
    let
        pieceBlocks =
            List.map (translateRelativeTo state.currentPiecePosition) <| getBlocks state.currentPiece
    in
        { state | fixatedBlocks = Set.union state.fixatedBlocks <| Set.fromList pieceBlocks }


countBlocksByRow : List ( Int, Int ) -> List ( Int, Int )
countBlocksByRow blocks =
    let
        incrementCount ( _, row ) countDict =
            Dict.update row (Just << (+) 1 << Maybe.withDefault 0) countDict
    in
        Dict.toList <| List.foldl incrementCount Dict.empty blocks


checkForCompleteRows : State -> State
checkForCompleteRows state =
    let
        blockCounts =
            countBlocksByRow <| Set.toList state.fixatedBlocks

        completeRows =
            Set.fromList <|
                List.filterMap
                    (\( row, count ) ->
                        if count == numCols then
                            Just row
                        else
                            Nothing
                    )
                    blockCounts

        maxCompletedRow =
            List.maximum <| Set.toList completeRows
    in
        case maxCompletedRow of
            Nothing ->
                state

            Just maxCompletedRow ->
                let
                    completedRowsRemoved =
                        List.filter (\( _, row ) -> not <| Set.member row completeRows) <| Set.toList state.fixatedBlocks

                    shiftDown ( x, row ) =
                        if row < maxCompletedRow then
                            ( x, row + Set.size completeRows )
                        else
                            ( x, row )

                    shiftedRows =
                        List.map shiftDown completedRowsRemoved
                in
                    { state | fixatedBlocks = Set.fromList <| shiftedRows, currentScore = state.currentScore + 100 * Set.size completeRows }


advance : State -> State
advance state =
    { state | currentPiece = state.nextPiece, currentPiecePosition = ( 0, 0 ) }


checkGameOver : State -> Model
checkGameOver state =
    if detectCollisions state then
        GameOver state.currentScore
    else
        Initialized state


fixateAndAdvance : State -> Model
fixateAndAdvance state =
    checkGameOver <| advance <| checkForCompleteRows <| fixate <| state


translateKeyDown : Keyboard.KeyCode -> Msg
translateKeyDown keycode =
    case keycode of
        38 ->
            Rotate

        40 ->
            Drop

        37 ->
            MoveLeft

        39 ->
            MoveRight

        _ ->
            NoOp


translateKeyUp : Keyboard.KeyCode -> Msg
translateKeyUp keycode =
    if keycode == 40 then
        StopDrop
    else
        NoOp


subscriptions : Model -> Sub Msg
subscriptions model =
    case model of
        Uninitialized ->
            Sub.none

        GameOver _ ->
            Sub.none

        Initialized state ->
            let
                tickInterval =
                    if state.dropping then
                        Time.second / 20
                    else
                        Time.second
            in
                Sub.batch
                    [ Keyboard.downs translateKeyDown
                    , Keyboard.ups translateKeyUp
                    , Time.every tickInterval <| always Tick
                    ]

        Error _ ->
            Sub.none


px : Int -> String
px i =
    toString i ++ "px"


pixel : Int -> Position -> Html msg
pixel size position =
    pixelWithItems size position []


pixelWithItems : Int -> Position -> List (Html msg) -> Html msg
pixelWithItems size { x, y } t =
    div
        [ style
            [ ( "background", "#000000" )
            , ( "width", toString size ++ "px" )
            , ( "height", toString size ++ "px" )
            , ( "top", px (y * size) )
            , ( "left", px (x * size) )
            , ( "position", "absolute" )
            ]
        ]
        t


renderOutline : List Position
renderOutline =
    let
        boardOutline =
            Raster.rectangle (Size 200 400) (Position 20 20)

        nextPieceOutline =
            Raster.rectangle (Size 80 80) (Position 240 20)
    in
        boardOutline ++ nextPieceOutline


renderBoard : Piece -> ( Int, Int ) -> List ( Int, Int ) -> List Position
renderBoard currentPiece ( curX, curY ) fixatedBlocks =
    let
        currentBlock =
            getBlocks currentPiece
                |> List.map (\( x, y ) -> Position (x + curX + 1) (y + curY + 1))

        blocks =
            fixatedBlocks
                |> List.map (\( x, y ) -> Position (x + 1) (y + 1))
    in
        currentBlock ++ blocks


renderNext : Piece -> List Position
renderNext nextPiece =
    getBlocks nextPiece
        |> List.map (\( x, y ) -> Position (x + 12) (y + 1))
