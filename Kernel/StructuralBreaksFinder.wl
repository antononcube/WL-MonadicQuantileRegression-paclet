
(* :Title: MonadicStructuralBreaksFinder *)
(* :Context: MonadicStructuralBreaksFinder` *)
(* :Author: Anton Antonov *)
(* :Date: 2019-06-30 *)
(* Created with the Wolfram Language Plugin for IntelliJ, see http://wlplugin.halirutan.de/ . *)

(* :Package Version: 0.5 *)
(* :Mathematica Version: 12 *)
(* :Copyright: (c) 2019 Anton Antonov *)
(* :Keywords: Chow Test, Quantile Regression, Structural Breaks *)
(* :Discussion:

   # In brief

   This package provides functions to for the Quantile Regression Monad package (QRMon):

     https://github.com/antononcube/MathematicaForPrediction/blob/master/MonadicProgramming/MonadicQuantileRegression.m .

   Here is an example usage:

      ts = FinancialData[Entity["Financial", "^SPX"], {{2015, 1, 1}, Date[]}];

      QRMonUnit[ts]⟹
        QRMonFindChowTestLocalMaxima[ts["Times"][[2 ;; -2 ;; 10]], {1, x, x^2}, "EchoPlots" -> True]⟹
        QRMonEchoValue;

   The function QRMonFindChowTestLocalMaxima takes the options of QRMon's functions
   QRMonQuantileRegression, QRMonFindLocalExtrema, and QRMonPlot.

   For example:

      QRMonUnit[ts]⟹
        QRMonFindChowTestLocalMaxima[
             "Knots" -> 20, InterpolationOrder -> 2,
             "NearestWithOutliers" -> False, "NumberOfProximityPoints" -> 5,
             "DateListPlot" -> True,
             "EchoPlots" -> True]⟹
       QRMonEchoValue⟹
       QRMonPlotStructuralBreakSplits[ImageSize -> 300, "DateListPlot" -> True];


   The plot function computes the structural breaks if the corresponding (first) argument is Automatic and
   the pipeline value is not a vector of regressor points.

       QRMonUnit[ts]⟹QRMonPlotStructuralBreakSplits[ImageSize -> 300, "DateListPlot" -> True]

   Anton Antonov
   Windermere, Florida, USA
   2019-06-30

*)


(**************************************************************)
(* Package definition                                         *)
(**************************************************************)

BeginPackage["AntonAntonov`MonadicQuantileRegression`StructuralBreaksFinder`"];

(*QRMonFindChowTestLocalMaxima::usage = "QRMonFindChowTestLocalMaxima[points : ( { _?NumberQ.. } | Automatic ), fitFuncs_, opts___] \*)
(*finds structural breaks in the data using the Chow Test. \*)
(*It takes as options the options of QRMonQuantileRegression, QRMonFindLocalExtrema, and QRMonPlot.";*)

(*QRMonFindStructuralBreaks::usage = "QRMonFindStructuralBreaks[points : ( { _?NumberQ.. } | Automatic ), fitFuncs_, opts___] \*)
(*finds structural breaks in the data using the Chow Test. \*)
(*It takes as options the options of QRMonQuantileRegression, QRMonFindLocalExtrema, and QRMonPlot. \*)
(*A synonym of QRMonFindChowTestLocalMaxima.";*)

(*QRMonPlotStructuralBreakSplits::usage = "QRMonPlotStructuralBreakSplits[ points, fitFuncs, opts___] \*)
(*makes a list of plots of structural break splits.";*)

Begin["`Private`"];

Needs["AntonAntonov`MonadicQuantileRegression`"];

(**************************************************************)
(* Find Chow Test local maxima                                *)
(**************************************************************)

Clear[QRMonFindChowTestLocalMaxima];

SyntaxInformation[QRMonFindChowTestLocalMaxima] = { "ArgumentsPattern" -> { _., _., OptionsPattern[] } };

Options[QRMonFindChowTestLocalMaxima] = { "Knots" -> 12, "NearestWithOutliers" -> False, "NumberOfProximityPoints" -> 15, "EchoPlots" -> False };

Options[QRMonFindChowTestLocalMaxima] =
    Join[
      { "Knots" -> 20, "EchoPlots" -> False },
      Options[QRMonQuantileRegression],
      Options[QRMonFindLocalExtrema],
      Options[QRMonPlot]
    ];

QRMonFindChowTestLocalMaxima[$QRMonFailure] := $QRMonFailure;

QRMonFindChowTestLocalMaxima[xs_, context_Association] := QRMonFindChowTestLocalMaxima[][xs, context];

QRMonFindChowTestLocalMaxima[][xs_, context_Association] := QRMonFindChowTestLocalMaxima[ Automatic, Automatic ][xs, context];

QRMonFindChowTestLocalMaxima[ opts : OptionsPattern[] ][xs_, context_Association] := QRMonFindChowTestLocalMaxima[ Automatic, Automatic, opts ][xs, context];

QRMonFindChowTestLocalMaxima[ points : ( { _?NumberQ.. } | Automatic ), fitFuncs_, opts : OptionsPattern[] ][xs_, context_Association] :=
    Block[{knots, echoPlotsQ, localMaximaPlotFunc, ctStats, res, data},

      knots = OptionValue["Knots"];

      echoPlotsQ = TrueQ[OptionValue["EchoPlots"]];

      ctStats =
          Fold[
            QRMonBind,
            QRMonUnit[ xs, context ],
            { QRMonChowTestStatistic[ points, fitFuncs ],
              QRMonTakeValue
            }];

      localMaximaPlotFunc = ListPlot;
      If[ TrueQ[ "DateListPlot" /. {opts} /. { "DateListPlot" -> False} ],
        localMaximaPlotFunc = DateListPlot
      ];

      res =
          Fold[
            QRMonBind,
            QRMonUnit[ ctStats ],
            { QRMonQuantileRegression[ knots, 0.5, FilterRules[ {opts}, Options[QRMonQuantileRegression] ] ],
              QRMonIfElse[ echoPlotsQ &,
                Function[{x, c}, QRMonPlot[ FilterRules[ {opts}, Options[QRMonPlot] ] ][x, c]],
                Function[{x, c}, QRMonUnit[x, c]]
              ],
              QRMonFindLocalExtrema[ FilterRules[ {opts}, Options[QRMonFindLocalExtrema] ] ],
              QRMonAddToContext["localExtrema"],
              QRMonIfElse[ echoPlotsQ &,
                Function[{x, c},
                  QRMonEchoFunctionContext[
                    localMaximaPlotFunc[#["data"],
                      FilterRules[ {opts}, Options[localMaximaPlotFunc] ],
                      GridLines -> {#["localExtrema", "localMaxima"][[All, 1]], None},
                      GridLinesStyle -> Pink, Joined -> False, Filling -> Axis,
                      PlotTheme -> "Detailed", ImageSize -> Large] &][x, c]
                ],
                Function[{x, c}, QRMonUnit[x, c]]
              ],
              QRMonTakeValue
            }];

      data = Fold[ QRMonBind, QRMonUnit[xs, context], { QRMonGetData, QRMonTakeValue } ];

      QRMonUnit[ res["localMaxima"], Join[ context, <| "data" -> data |> ]  ]
    ];

QRMonFindChowTestLocalMaxima[___][xs_, context_Association] :=
    Block[{},
      Echo["The first argument is expected to be a list of points;" <>
          "the second argument is expected to be a list of fit functions.",
        "QRMonFindChowTestLocalMaxima:"
      ];
      $QRMonFailure
    ];

Clear[QRMonFindStructuralBreaks];
QRMonFindStructuralBreaks = QRMonFindChowTestLocalMaxima;


(**************************************************************)
(* Plot structural break splits                               *)
(**************************************************************)

Clear[VectorOfRegressorPointsQ];

VectorOfRegressorPointsQ[ vec_?VectorQ, range : {_?NumberQ, _?NumberQ} ] :=
    VectorQ[vec, range[[1]] <= # <= range[[2]] & ];

VectorOfRegressorPointsQ[___] := False;


Clear[QRMonPlotStructuralBreakSplits];

SyntaxInformation[QRMonPlotStructuralBreakSplits] = { "ArgumentsPattern" -> { _., _., OptionsPattern[] } };

Options[QRMonPlotStructuralBreakSplits] = { "LeftPartColor" -> Gray, "RightPartColor" -> Red, "DateListPlot" -> False, "Echo" -> True };

Options[QRMonPlotStructuralBreakSplits] = Join[ Options[QRMonPlotStructuralBreakSplits], Options[QRMonPlot] ];

QRMonPlotStructuralBreakSplits[$QRMonFailure] := $QRMonFailure;

QRMonPlotStructuralBreakSplits[xs_, context_Association] := QRMonPlotStructuralBreakSplits[][xs, context];

QRMonPlotStructuralBreakSplits[][xs_, context_Association] := QRMonPlotStructuralBreakSplits[ Automatic, Automatic, Options[QRMonPlotStructuralBreakSplits] ][xs, context];

QRMonPlotStructuralBreakSplits[ opts : OptionsPattern[] ][xs_, context_Association] :=
    QRMonPlotStructuralBreakSplits[ Automatic, Automatic, opts ][xs, context];

QRMonPlotStructuralBreakSplits[ splitPoints : ( { _?NumberQ.. } | Automatic ), opts : OptionsPattern[] ][xs_, context_Association] :=
    QRMonPlotStructuralBreakSplits[ splitPoints, Automatic, opts ][xs, context];

QRMonPlotStructuralBreakSplits[ splitPointsArg : ( { _?NumberQ.. } | Automatic ), fitFuncsArg_, opts : OptionsPattern[] ][xs_, context_Association] :=
    Block[{ fitFuncs = fitFuncsArg, splitPoints = splitPointsArg,
      leftPartColor, rightPartColor, dateListPlotQ, echoPlotsQ,
      data, chowTestStat, res},

      leftPartColor = OptionValue[ QRMonPlotStructuralBreakSplits, "LeftPartColor" ];
      rightPartColor = OptionValue[ QRMonPlotStructuralBreakSplits, "RightPartColor" ];
      dateListPlotQ = TrueQ[ OptionValue[ QRMonPlotStructuralBreakSplits, "DateListPlot" ] ];
      echoPlotsQ = TrueQ[ OptionValue[ QRMonPlotStructuralBreakSplits, "Echo" ] ];

      If[ TrueQ[ fitFuncs === Automatic ],
        fitFuncs = {1, Global`x};
      ];

      If[ !( VectorQ[splitPoints, NumberQ] || TrueQ[ splitPoints === Automatic ] ),
        Echo["The first argument is expected to be a list of regressor split points.", "QRMonPlotStructuralBreakSplits:"];
        Return[$QRMonFailure];
      ];

      data = Fold[ QRMonBind, QRMonUnit[xs, context], { QRMonGetData, QRMonTakeValue } ];
      If[ TrueQ[ data === $QRMonFailure ],
        Return[$QRMonFailure];
      ];


      If[ TrueQ[ splitPoints === Automatic ],

        splitPoints = xs;

        Which[

          MatrixQ[splitPoints] && VectorOfRegressorPointsQ[ splitPoints[[All, 1]], MinMax[ data[[All, 1]] ] ],
          splitPoints = splitPoints[[All, 1]],

          !VectorOfRegressorPointsQ[ splitPoints, MinMax[ data[[All, 1]] ] ],
          (* If split points is not a vector of regressor points. *)
          splitPoints =
              QRMonUnit[data] \[DoubleLongRightArrow]
                  QRMonFindChowTestLocalMaxima["Knots" -> 20, "NearestWithOutliers" -> True, "NumberOfProximityPoints" -> 5, "EchoPlots" -> False] \[DoubleLongRightArrow]
                  QRMonTakeValue;

          If[ TrueQ[ splitPoints === $QRMonFailure ],
            Return[$QRMonFailure];
          ];

          splitPoints = splitPoints[[All, 1]];
        ]

      ];

      res = Association @
          Table[
            Block[{data1, data2},
              data1 = Select[data, #[[1]] <= sp &];
              data2 = Select[data, #[[1]] > sp &];
              chowTestStat = (QRMonUnit[data] \[DoubleLongRightArrow] QRMonChowTestStatistic[sp, fitFuncs] \[DoubleLongRightArrow] QRMonTakeValue)[[1, 2]];
              {sp, chowTestStat} ->
                  Show[{
                    QRMonUnit[data1] \[DoubleLongRightArrow]
                        QRMonFit[fitFuncs] \[DoubleLongRightArrow]
                        QRMonSetDataPlotOptions[{PlotStyle -> leftPartColor}] \[DoubleLongRightArrow]
                        QRMonPlot[ "DateListPlot" -> dateListPlotQ, "Echo" -> False, Sequence @@ FilterRules[{opts}, Options[QRMonPlot]] ] \[DoubleLongRightArrow]
                        QRMonTakeValue,
                    QRMonUnit[data2] \[DoubleLongRightArrow]
                        QRMonFit[fitFuncs] \[DoubleLongRightArrow]
                        QRMonSetDataPlotOptions[{PlotStyle -> rightPartColor}] \[DoubleLongRightArrow]
                        QRMonPlot[ "DateListPlot" -> dateListPlotQ, "Echo" -> False, PlotLegends -> None, Sequence @@ FilterRules[{opts}, Options[QRMonPlot]] ] \[DoubleLongRightArrow]
                        QRMonTakeValue},
                    PlotRange -> All]
            ],
            {sp, splitPoints}];

      If[ TrueQ[echoPlotsQ],
        Echo[
          KeyValueMap[ Show[#2, PlotLabel -> Grid[{{"Point:", #1[[1]]}, {"Chow Test statistic:", #1[[2]] }}, Alignment -> Left]]&, res],
          "structural break splits:"
        ]
      ];

      QRMonUnit[ res, context ]
    ];

QRMonPlotStructuralBreakSplits[___][xs_, context_Association] :=
    Block[{},
      Echo["The first argument is expected to be a list of points;" <>
          "the second argument is expected to be a list of fit functions.",
        "QRMonPlotStructuralBreakSplits:"
      ];
      $QRMonFailure
    ];

(**************************************************************)
(* Find structural breaks                                     *)
(**************************************************************)

(*Clear[QRMonFindStructuralBreaks];*)

(*QRMonFindStructuralBreaks[$QRMonFailure] := $QRMonFailure;*)

(*QRMonFindStructuralBreaks[xs_, context_] := QRMonFindStructuralBreaks[][xs, context];*)

(*QRMonFindStructuralBreaks[][xs_, context_] := QRMonFindStructuralBreaks[ Automatic, {1, x} ][xs, context];*)

(*QRMonFindStructuralBreaks[ points : ({_?NumericQ..} | Automatic), fitFuncs_List ] :=*)
(*    Block[{},*)


(*    ];*)

End[]; (* `Private` *)

EndPackage[]