
(* :Title: MonadicQuantileRegression *)
(* :Context: MonadicQuantileRegression` *)
(* :Author: Anton Antonov *)
(* :Date: 2018-06-03 *)

(* :Package Version: 1.0 *)
(* :Mathematica Version: 11.3 *)
(* :Copyright: (c) 2018 Anton Antonov *)
(* :Keywords: quantile regression, monad, workflow *)
(* :Discussion:

   # In brief

   This package provides a software monad implementation for Quantile regression workflows.
   The functionalities of the package are described in [1,2].


   # Usage example

       sqPoints = Table[{x, Sqrt[x]}, {x, 1/2, 8, 0.1}];
       ListPlot[sqPoints]

       Import["https://raw.githubusercontent.com/antononcube/MathematicaForPrediction/master/MonadicProgramming/MonadicQuantileRegression.m"]

       p =
         QRMonUnit[sqPoints]⟹
          QRMonQuantileRegressionFit[20, 0.5]⟹
          QRMonPlot[]⟹
          QRMonErrorPlots⟹
          QRMonErrors⟹
          QRMonEchoFunctionValue["Relative errors summary:", ResourceFunction["RecordsSummary"] /@ # &];

       qFunc = (p⟹QRMonTakeRegressionFunctions)[0.5];

       Simplify[qFunc[x]]

       (* 27.05 - 245.125 x + 1011.11 x^2 - 2479.16 x^3 + 4080.66 x^4 - 4812.07 x^5 +
         4233.13 x^6 - 2853.77 x^7 + 1501.85 x^8 - 624.791 x^9 + 207.112 x^10 -
         54.9287 x^11 + 11.6595 x^12 - 1.97386 x^13 + 0.264376 x^14 -
         0.0276295 x^15 + 0.00220351 x^16 - 0.000129425 x^17 + 5.27363*10^-6 x^18 -
         1.3307*10^-7 x^19 + 1.56554*10^-9 x^20 *)

   Instead of doing the fit with Chebyshev polynomials basis through QRMonQuantileRegressionFit one can use
   a B-spline basis with QRMonQuantileRegression; see [1,2] for details.


   # References

   [1] Anton Antonov, "A monad for Quantile Regression workflows", (2018), MathematicaForPrediction at WordPress.
       URL: https://mathematicaforprediction.wordpress.com/2018/08/01/a-monad-for-quantile-regression-workflows/ .

   [2] Anton Antonov, "A monad for Quantile Regression workflows", (2018), MathematicaForPrediction at GitHub.
       URL: https://github.com/antononcube/MathematicaForPrediction/blob/master/MarkdownDocuments/A-monad-for-Quantile-Regression-workflows.md .


   Anton Antonov
   June-July 2018
   Windermere, Florida, USA

*)



BeginPackage["AntonAntonov`MonadicQuantileRegression`QRMon`"];


Begin["`Private`"];

(*Needs["MathematicaForPredictionUtilities`"];*)
Needs["AntonAntonov`MonadicQuantileRegression`"];
Needs["AntonAntonov`MonadMakers`"];
Needs["AntonAntonov`QuantileRegression`"];
Needs["AntonAntonov`OutlierIdentifiers`"];

(**************************************************************)
(* Generation                                                 *)
(**************************************************************)

(* Generate base functions of QRMon monad (through StMon.) *)

GenerateStateMonadCode[ "AntonAntonov`MonadicQuantileRegression`QRMon", "FailureSymbol" -> $QRMonFailure, "StringContextNames" -> False ];

GenerateMonadAccessors[
  "AntonAntonov`MonadicQuantileRegression`QRMon",
  {"data", "regressionFunctions", "outliers", "outlierRegressionFunctions", "net",
    "dataPlotOptions", "regressionFunctionsPlotOptions"},
  "FailureSymbol" -> $QRMonFailure ];


(**************************************************************)
(* Setters / getters                                          *)
(**************************************************************)

(* This is has to be re-implemented because of the use of QRMonGetData. *)
ClearAll[QRMonTakeData];

SyntaxInformation[QRMonGetData] = { "ArgumentsPattern" -> { } };

QRMonTakeData[$QRMonFailure] := $QRMonFailure;
QRMonTakeData[][$QRMonFailure] := $QRMonFailure;
QRMonTakeData[xs_, context_] := QRMonTakeData[][xs, context];
QRMonTakeData[][xs_, context_] := QRMonBind[ QRMonGetData[xs, context], QRMonTakeValue ];
QRMonTakeData[__][___] := $QRMonFailure;


Clear[QRMonSetNet];
QRMonSetNet[$QRMonFailure] := $QRMonFailure;
QRMonSetNet[xs_, context_] := QRMonSetNet[][xs, context];
QRMonSetNet[][xs_, context_] :=
    Block[{net},
      net =
          NetChain[{
            LinearLayer[15], BatchNormalizationLayer[],
            ElementwiseLayer[Tanh], LinearLayer[10], BatchNormalizationLayer[],
            ElementwiseLayer[Tanh], LinearLayer[1]},
            "Input" -> 1, "Output" -> "Scalar" ];
      QRMonUnit[ xs, Join[ context, <|"net" -> net|> ] ]
    ];
QRMonSetNet[net_NetChain][xs_, context_] := QRMonUnit[ xs, Join[ context, <|"net" -> net|> ] ];
QRMonSetNet[__][___] := $QRMonFailure;


(**************************************************************)
(* DataToNormalForm                                           *)
(**************************************************************)

Clear[DataToNormalForm];

DataToNormalForm[data_, functionName_String] :=
    Which[
      MatrixQ[data, NumericQ] && Dimensions[data][[2]] == 2,
      data,

      VectorQ[data, NumericQ],
      Transpose[{ Range[Length[data]], data }],

      TrueQ[ Head[data] === Dataset ],
      (* DatasetToMatrix is implemented in MathematicaForPredictionUtilities.m *)
      DatasetToMatrix[
        data,
        "ExpectedColumnNames" -> {"Regressor", "Value"},
        "FunctionName" -> functionName,
        "FailureSymbol" -> $QRMonFailure
      ]
    ];


(**************************************************************)
(* GetData                                                    *)
(**************************************************************)

Clear[QRMonGetData];

SyntaxInformation[QRMonGetData] = { "ArgumentsPattern" -> { } };

QRMonGetData[$QRMonFailure] := $QRMonFailure;

QRMonGetData[][xs_, context_] := QRMonGetData[xs, context];

QRMonGetData[xs_, context_] :=
    Block[{data},

      Which[

        KeyExistsQ[context, "data"] && MatrixQ[context["data"], NumericQ] && Dimensions[context["data"]][[2]] == 2,
        QRMonUnit[ context["data"], context],

        KeyExistsQ[context, "data"] && VectorQ[context["data"], NumericQ],
        data = DataToNormalForm[context["data"], "QRMonGetData"];
        QRMonUnit[ data, Join[context, <| "data" -> data |>] ],

        KeyExistsQ[context, "data"] && TrueQ[ Head[context["data"]] === Dataset ],
        data = DataToNormalForm[context["data"], "QRMonGetData"];
        If[ TrueQ[data === $QRMonFailure],
          $QRMonFailure,
          QRMonUnit[ SetPrecision[data, Precision[data]], context]
        ],

        KeyExistsQ[context, "data"] && MatchQ[context["data"], (_TimeSeries | _TemporalData)],
        data = context["data"]["Path"] /. Quantity[x_, u_] :> x;
        QRMonUnit[ SetPrecision[data, Precision[data]], context],

        MatrixQ[xs, NumericQ] && Dimensions[xs][[2]] == 2,
        QRMonUnit[xs, context],

        VectorQ[xs, NumericQ],
        QRMonUnit[ Transpose[{ Range[Length[xs]], xs }], context],

        TrueQ[ Head[xs] === Dataset ],
        data = DataToNormalForm[xs, "QRMonGetData"];
        If[ TrueQ[data === $QRMonFailure],
          $QRMonFailure,
          QRMonUnit[ SetPrecision[data, Precision[data]], context]
        ],

        MatchQ[xs, (_TimeSeries | _TemporalData)],
        data = xs["Path"] /. Quantity[x_, u_] :> x;
        QRMonUnit[ SetPrecision[data, Precision[data]], context],

        True,
        Echo["Cannot find data.", "GetData:"];
        $QRMonFailure
      ]

    ];

QRMonGetData[___][xs_, context_Association] := $QRMonFailure;


(**************************************************************)
(* Echo data summary                                          *)
(**************************************************************)

Clear[QRMonEchoDataSummary];

SyntaxInformation[QRMonEchoDataSummary] = { "ArgumentsPattern" -> { } };

QRMonEchoDataSummary[$QRMonFailure] := $QRMonFailure;

QRMonEchoDataSummary[xs_, context_] := QRMonEchoDataSummary[][xs, context];

QRMonEchoDataSummary[][xs_, context_] :=
    Fold[ QRMonBind, QRMonUnit[xs, context], { QRMonGetData, QRMonEchoFunctionValue["Data summary:", ResourceFunction["RecordsSummary"][#, {"Regressor", "Value"}]& ] } ]

QRMonEchoDataSummary[___][__] := $QRMonFailure;


(**************************************************************)
(* DeleteMissing                                             *)
(**************************************************************)

Clear[QRMonDeleteMissing];

SyntaxInformation[QRMonDeleteMissing] = { "ArgumentsPattern" -> { } };

QRMonDeleteMissing[$QRMonFailure] := $QRMonFailure;

QRMonDeleteMissing[xs_, context_] := QRMonDeleteMissing[][xs, context];

QRMonDeleteMissing[][xs_, context_] :=
    Block[{data},

      data = QRMonTakeData[xs, context];

      If[ data === $QRMonFailure,
        $QRMonFailure,
        (*ELSE*)
        data = DeleteMissing[data, 1, 2];
        QRMonUnit[ data, Join[ context, <|"data" -> data|>] ]
      ]
    ];

QRMonDeleteMissing[___][__] := $QRMonFailure;


(**************************************************************)
(* Rescale                                                    *)
(**************************************************************)

Clear[QRMonRescale];

SyntaxInformation[QRMonRescale] = { "ArgumentsPattern" -> { OptionsPattern[] } };

Options[QRMonRescale] = {Axes -> {True, False}};

QRMonRescale[$QRMonFailure] := $QRMonFailure;

QRMonRescale[xs_, context_] := QRMonRescale[][xs, context];

QRMonRescale[opts : OptionsPattern[]][xs_, context_] :=
    Block[{data, axesOpt},

      axesOpt = OptionValue[QRMonRescale, Axes];

      data = QRMonTakeData[ xs, context ];

      If[data === $QRMonFailure, Return[$QRMonFailure]];

      Which[
        TrueQ[ axesOpt == {False, False}] || TrueQ[ !axesOpt ] || TrueQ[ axesOpt === None ],
        QRMonUnit[xs, context],

        TrueQ[axesOpt] || TrueQ[axesOpt == {True, True}] ||
            TrueQ[ ToLowerCase[axesOpt] == "both" || ToLowerCase[axesOpt] == "path" || axesOpt === All ] ||
            TrueQ[ ListQ[axesOpt] && Length[Intersection[axesOpt, {"x", "y", "time"}]] == 2 ] ||
            TrueQ[ ListQ[axesOpt] && Length[Intersection[axesOpt, {"x", "value", "time"}]] == 2 ],
        data = Transpose[Rescale /@ Transpose[data]];
        QRMonUnit[ data, Join[ context, <|"data" -> data|>] ],

        TrueQ[ axesOpt == {True, False}] ||
            TrueQ[ axesOpt == "x" || axesOpt == "t"],
        data = Transpose[{Rescale[data[[All, 1]]], data[[All, 2]]}];
        QRMonUnit[ data, Join[ context, <|"data" -> data|>] ],

        TrueQ[ axesOpt == {False, True}] ||
            TrueQ[ axesOpt == "y" || axesOpt == "value"],
        data = Transpose[{data[[All, 1]], Rescale[data[[All, 2]]]}];
        QRMonUnit[ data, Join[ context, <|"data" -> data|>] ],

        True,
        $QRMonFailure
      ]
    ];

QRMonRescale[___][__] := $QRMonFailure;


(**************************************************************)
(* LeastSquaresFit                                            *)
(**************************************************************)

Clear[QRMonLeastSquaresFit];

SyntaxInformation[QRMonLeastSquaresFit] = { "ArgumentsPattern" -> { _, _. } };

QRMonLeastSquaresFit[$QRMonFailure] := $QRMonFailure;

QRMonLeastSquaresFit[xs_, context_Association] := $QRMonFailure;

QRMonLeastSquaresFit[n_Integer][xs_, context_] :=
    QRMonLeastSquaresFit[{ n, {-0.95, 0.95} }][xs, context];

(* This signature is not that needed for LeastSquaresFit, it is implemented for symmetry with QuantileRegressionFit . *)
QRMonLeastSquaresFit[{ n_Integer, r : {_?NumericQ, _?NumericQ} }][xs_, context_] :=
    Fold[
      QRMonBind,
      QRMonUnit[xs, context],
      {QRMonGetData,
        QRMonLeastSquaresFit[Table[ChebyshevT[i, Rescale[x, MinMax[#[[All, 1]]], r]], {i, 0, n}], x][##]&}
    ];

QRMonLeastSquaresFit[funcs_List][xs_, context_] :=
    Block[{var},

      var =
          With[{globalQ = Context@# === "Global`" &},
            DeleteDuplicates@Cases[funcs, _Symbol?globalQ, Infinity]
          ];

      If[ Length[var] == 0,
        $QRMonFailure,
        (*ELSE*)
        QRMonLeastSquaresFit[funcs, First[var]][xs, context]
      ]
    ];

QRMonLeastSquaresFit[funcs_List, var_Symbol][xs_, context_] :=
    Block[{data, qFunc},

      data = QRMonBind[ QRMonGetData[xs, context], QRMonTakeValue ];

      qFunc = Fit[data, funcs, var];

      qFunc = Function[ Evaluate[ qFunc /. var -> Slot[1] ] ];

      QRMonUnit[qFunc,
        Join[context,
          <|"data" -> data,
            "regressionFunctions" -> Join[ Lookup[context, "regressionFunctions", <||>], <| "mean" -> qFunc |> ] |>
        ]
      ]
    ];

QRMonLeastSquaresFit[___][__] := $QRMonFailure;


Clear[QRMonFit];
QRMonFit = QRMonLeastSquaresFit;


(**************************************************************)
(* Quantile regression                                        *)
(**************************************************************)

Clear[QRMonQuantileRegression];

SyntaxInformation[QRMonQuantileRegression] = { "ArgumentsPattern" -> { _., _., OptionsPattern[] } };

Options[QRMonQuantileRegression] =
    Join[
      { "Knots" -> 12, "Probabilities" -> {0.25, 0.5, 0.75} },
      Options[QuantileRegression]
    ];

Options[QRMonQuantileRegression] =
    ReplaceAll[
      Options[QRMonQuantileRegression],
      HoldPattern[Method -> _] -> ( Method -> {LinearProgramming, Method -> "CLP", Tolerance -> 10^(-3)} ) ];

QRMonQuantileRegression[$QRMonFailure] := $QRMonFailure;

QRMonQuantileRegression[xs_, context_Association] := QRMonQuantileRegression[ Options[QRMonQuantileRegression] ][xs, context];

QRMonQuantileRegression[][xs_, context_Association] := QRMonQuantileRegression[ Options[QRMonQuantileRegression] ][xs, context];

QRMonQuantileRegression[opts : OptionsPattern[]][xs_, context_Association] :=
    Block[{knots, probabilities},

      knots = OptionValue[QRMonQuantileRegression, "Knots"];

      If[ ! MatchQ[ knots, ( _Integer | { _?NumberQ..} ) ],
        Echo[
          "The value of the option \"Knots\" is expected to be a knots specification, (_Integer | {_?NumberQ..}). ",
          "QRMonQuantileRegression:"];
        Return[$QRMonFailure];
      ];

      probabilities = OptionValue[QRMonQuantileRegression, "Probabilities"];

      If[ ! MatchQ[ probabilities, ( _?NumberQ | { _?NumberQ..} ) ],
        Echo[
          "The value of the option \"Probabilities\" is expected to be a probabilities specification, (_?NumberQ | {_?NumberQ..}). ",
          "QRMonQuantileRegression:"];
        Return[$QRMonFailure];
      ];

      probabilities = If[ NumberQ[probabilities], {probabilities}, probabilities ];

      QRMonQuantileRegression[knots, probabilities, opts][xs, context]
    ];

QRMonQuantileRegression[knots : (_Integer | {_?NumberQ ..}), opts : OptionsPattern[]][xs_, context_] :=
    QRMonQuantileRegression[knots, {0.25, 0.5, 0.75}, opts][xs, context];

QRMonQuantileRegression[knots : (_Integer | {_?NumberQ ..}), p_?NumberQ, opts : OptionsPattern[]][xs_, context_] :=
    QRMonQuantileRegression[knots, {p}, opts][xs, context];

QRMonQuantileRegression[knots : (_Integer | {_?NumberQ ..}), ps : {_?NumberQ..}, opts : OptionsPattern[]][xs_, context_] :=
    Block[{data, qFuncs},

      data = QRMonBind[ QRMonGetData[xs, context], QRMonTakeValue ];

      qFuncs = QuantileRegression[data, knots, ps, FilterRules[ {opts}, Options[QuantileRegression] ] ];

      If[ ListQ[qFuncs] && Length[qFuncs] == Length[ps],
        qFuncs = AssociationThread[ps, qFuncs];
        QRMonUnit[qFuncs, Join[context, <|"data" -> data, "regressionFunctions" -> Join[ Lookup[context, "regressionFunctions", <||>], qFuncs] |> ] ],
        (* ELSE *)
        $QRMonFailure
      ]
    ];

QRMonQuantileRegression[___][__] :=
    Block[{},
      Echo[
        StringJoin[
          "The first argument is expected to be a knots specification, ( _Integer | {_?NumberQ..} ). ",
          "The second optional argument is expected to be a probabilities specification, ( _?NumberQ | {_?NumberQ..} )."
        ],
        "QRMonQuantileRegression:"
      ];

      $QRMonFailure
    ];


Clear[QRMonRegression];
QRMonRegression = QRMonQuantileRegression;


(**************************************************************)
(* Quantile regression fit                                    *)
(**************************************************************)

Clear[QRMonQuantileRegressionFit];

SyntaxInformation[QRMonQuantileRegressionFit] = { "ArgumentsPattern" -> { _., _., _., OptionsPattern[] } };

Options[QRMonQuantileRegressionFit] =
    Join[
      { "Functions" -> 12, "Variable" -> Automatic, "Probabilities" -> {0.25, 0.5, 0.75} },
      Options[QuantileRegressionFit]
    ];

Options[QRMonQuantileRegressionFit] =
    ReplaceAll[
      Options[QRMonQuantileRegressionFit],
      HoldPattern[Method -> _] -> ( Method -> {LinearProgramming, Method -> "CLP"} ) ];

QRMonQuantileRegressionFit[$QRMonFailure] := $QRMonFailure;

QRMonQuantileRegressionFit[xs_, context_Association] := QRMonQuantileRegressionFit[ Options[QRMonQuantileRegressionFit] ][xs, context];

QRMonQuantileRegressionFit[][xs_, context_Association] := QRMonQuantileRegressionFit[ Options[QRMonQuantileRegressionFit] ][xs, context];

QRMonQuantileRegressionFit[opts : OptionsPattern[]][xs_, context_Association] :=
    Block[{funcs, var, probabilities},

      funcs = OptionValue[QRMonQuantileRegressionFit, "Functions"];

      If[ ! ( IntegerQ[funcs] || ListQ[ funcs ] ),
        Echo[
          "The value of the option \"Functions\" is expected to be a list of functions or an integer. ",
          "QRMonQuantileRegressionFit:"];
        Return[$QRMonFailure];
      ];

      var = OptionValue[QRMonQuantileRegressionFit, "Variable"];

      If[ ! ( TrueQ[var === Automatic] || TrueQ[ Head[var] === Symbol ] ) ,
        Echo[
          "The value of the option \"Variabls\" is expected to be a symbol or Automatic. ",
          "QRMonQuantileRegressionFit:"];
        Return[$QRMonFailure];
      ];

      probabilities = OptionValue[QRMonQuantileRegressionFit, "Probabilities"];

      If[ ! MatchQ[ probabilities, ( _?NumberQ | { _?NumberQ..} ) ],
        Echo[
          "The value of the option \"Probabilities\" is expected to be a probabilities specification, (_?NumberQ | {_?NumberQ..}). ",
          "QRMonQuantileRegressionFit:"];
        Return[$QRMonFailure];
      ];

      probabilities = If[ NumberQ[probabilities], {probabilities}, probabilities ];

      If[ IntegerQ[funcs],
        QRMonQuantileRegressionFit[funcs, probabilities, opts][xs, context],
        (* ELSE *)
        QRMonQuantileRegressionFit[funcs, var, probabilities, opts][xs, context]
      ]
    ];

QRMonQuantileRegressionFit[funcs : (_List | _Integer), opts : OptionsPattern[]][xs_, context_] :=
    QRMonQuantileRegressionFit[funcs, {0.25, 0.5, 0.75}, opts][xs, context];

QRMonQuantileRegressionFit[funcs_List, p_?NumberQ, opts : OptionsPattern[]][xs_, context_] :=
    QRMonQuantileRegressionFit[funcs, {p}, opts][xs, context];

QRMonQuantileRegressionFit[n_Integer, args___][xs_, context_] :=
    QRMonQuantileRegressionFit[{ n, {-0.95, 0.95} }, args][xs, context];

QRMonQuantileRegressionFit[{ n_Integer, r : {_?NumericQ, _?NumericQ} }, args___][xs_, context_] :=
    Fold[
      QRMonBind,
      QRMonUnit[xs, context],
      {QRMonGetData,
        QRMonQuantileRegressionFit[Table[ChebyshevT[i, Rescale[x, MinMax[#[[All, 1]]], r]], {i, 0, n}], x, args][##]&}
    ];

QRMonQuantileRegressionFit[funcs_List, ps : {_?NumberQ..}, opts : OptionsPattern[]][xs_, context_] :=
    QRMonQuantileRegressionFit[funcs, Automatic, ps, opts][xs, context];

QRMonQuantileRegressionFit[funcs_List, Automatic, ps : {_?NumberQ..}, opts : OptionsPattern[]][xs_, context_] :=
    Block[{var},

      var =
          With[{globalQ = Context@# === "Global`" &},
            DeleteDuplicates@Cases[funcs, _Symbol?globalQ, Infinity]
          ];

      If[ Length[var] == 0,
        $QRMonFailure,
        (*ELSE*)
        QRMonQuantileRegressionFit[funcs, First[var], ps, opts][xs, context]
      ]
    ];

QRMonQuantileRegressionFit[funcs_List, var_Symbol, opts : OptionsPattern[]][xs_, context_] :=
    QRMonQuantileRegressionFit[funcs, var, {0.25, 0.5, 0.75}, opts][xs, context];

QRMonQuantileRegressionFit[funcs_List, var_Symbol, ps : {_?NumberQ..}, opts : OptionsPattern[]][xs_, context_] :=
    Block[{data, qFuncs},

      data = QRMonBind[ QRMonGetData[xs, context], QRMonTakeValue ];

      qFuncs = QuantileRegressionFit[data, funcs, var, ps, FilterRules[ {opts}, Options[QuantileRegressionFit] ] ];

      If[ ListQ[qFuncs] && Length[qFuncs] == Length[ps],
        qFuncs = Map[Function[{expr}, Function[Evaluate[expr /. var -> Slot[1]]]], qFuncs];
        qFuncs = AssociationThread[ps, qFuncs];
        QRMonUnit[qFuncs, Join[context, <|"data" -> data, "regressionFunctions" -> Join[ Lookup[context, "regressionFunctions", <||>], qFuncs] |> ] ],
        (* ELSE *)
        $QRMonFailure
      ]
    ];

QRMonQuantileRegressionFit[___][__] := $QRMonFailure;


Clear[QRMonRegressionFit];
QRMonRegressionFit = QRMonQuantileRegressionFit;


(**************************************************************)
(* Net regression                                            *)
(**************************************************************)

Clear[QRMonNetRegression];

Options[QRMonNetRegression] = Prepend[Options[NetTrain], InterpolationOrder -> 3];

QRMonNetRegression[$QRMonFailure] := $QRMonFailure;

QRMonNetRegression[xs_, context_Association] := QRMonNetRegression[][xs, context];

QRMonNetRegression[][xs_, context_Association] := QRMonNetRegression[0.75][xs, context];

QRMonNetRegression[opts : OptionsPattern[]][xs_, context_] :=
    QRMonNetRegression[0.75, opts][xs, context];

QRMonNetRegression[splitRatio_?NumberQ, opts : OptionsPattern[]][xs_, context_] :=
    Block[{interpolationOrder, data, qFunc, netRegressionPoints, trainingData, testData, trainedNet, lowestVal},

      If[ ! KeyExistsQ[context, "net"],
        Echo["Cannot find a neural net. (Context key \"net\".).", "QRMonNetRegression:"];
        Return[$QRMonFailure]
      ];

      interpolationOrder = OptionValue[QRMonNetRegression, InterpolationOrder];

      data = QRMonBind[ QRMonGetData[xs, context], QRMonTakeValue ];

      {trainingData, testData} = TakeDrop[RandomSample[data], Floor[splitRatio * Length[data]]];
      trainingData = Rule @@@ trainingData;
      trainingData[[All, 1]] = List /@ trainingData[[All, 1]];
      testData = Rule @@@ testData;
      testData[[All, 1]] = List /@ testData[[All, 1]];

      {trainedNet, lowestVal} =
          NetTrain[
            context["net"], trainingData, {"TrainedNet", "ValidationLoss"},
            ValidationSet -> testData,
            DeleteCases[ {opts}, HoldPattern[InterpolationOrder -> _] ]
          ];

      netRegressionPoints = Transpose[{data[[All, 1]], trainedNet /@ data[[All, 1]]}];
      qFunc = Interpolation[ Union[netRegressionPoints], InterpolationOrder -> Round[interpolationOrder] ];

      QRMonUnit[qFunc,
        Join[context,
          <|"data" -> data,
            "net" -> trainedNet,
            "netRegressionPoints" -> netRegressionPoints,
            "regressionFunctions" -> Join[ Lookup[context, "regressionFunctions", <||>], <| "net" -> qFunc |> ] |>
        ]
      ]
    ] /; 0 < splitRatio < 1;

QRMonNetRegression[___][__] :=
    Block[{},
      Echo["The first argument is expected to be a split ratio specification: a number between 0 and 1.", "QRMonNetRegression:"];
      $QRMonFailure
    ];


(**************************************************************)
(* Evaluate                                                   *)
(**************************************************************)
(* See InterpolationFunction[___]["Evaluate"[{0.2, 0.3, 1}]] *)
(* Probably can be optimized. *)

Clear[QRMonEvaluate];

SyntaxInformation[QRMonEvaluate] = { "ArgumentsPattern" -> {_} };

QRMonEvaluate[$QRMonFailure] := $QRMonFailure;

QRMonEvaluate[xs_, context_Association] := $QRMonFailure;

QRMonEvaluate[___][$QRMonFailure] := $QRMonFailure;

QRMonEvaluate[n_?AtomQ][x_, context_] :=
    If[KeyExistsQ[context, "regressionFunctions"],
      QRMonUnit[ Map[#[n]&, context["regressionFunctions"] ], context ],
      (*ELSE*)
      $QRMonFailure
    ];

QRMonEvaluate[arr_List][x_, context_] :=
    If[KeyExistsQ[context, "regressionFunctions"],
      QRMonUnit[ Map[Function[{qf}, Map[qf, arr, {-1}]], context["regressionFunctions"] ], context ],
      (*ELSE*)
      $QRMonFailure
    ];

QRMonEvaluate[___][__] := $QRMonFailure;


(**************************************************************)
(* Plot                                                       *)
(**************************************************************)

Clear[QRMonPlot];

SyntaxInformation[QRMonPlot] = { "ArgumentsPattern" -> {OptionsPattern[]} };

Options[QRMonPlot] = Join[ {"Echo" -> True, "DateListPlot" -> False}, Options[ListPlot] ];

QRMonPlot[QRMonPlot] := $QRMonFailure;

QRMonPlot[xs_, context_Association] := QRMonPlot[][xs, context];

QRMonPlot[opts : OptionsPattern[]][xs_, context_] :=
    Block[{data, res, listPlotFunc = ListPlot, listPlotOpts, plotOpts},

      data = QRMonTakeData[xs, context];

      If[data === $QRMonFailure, Return[$QRMonFailure]];

      If[ TrueQ[OptionValue[QRMonPlot, "DateListPlot"]], listPlotFunc = DateListPlot ];

      listPlotOpts = Normal @ KeyTake[ {opts}, First /@ Options[listPlotFunc]];
      plotOpts = Normal @ KeyTake[ {opts}, First /@ Options[Plot]];
      plotOpts = DeleteCases[plotOpts, HoldPattern[PlotStyle -> _] ];

      If[ KeyExistsQ[context, "dataPlotOptions"],
        listPlotOpts = Join[ context["dataPlotOptions"], listPlotOpts];
      ];

      If[ KeyExistsQ[context, "regressionFunctionsPlotOptions"],
        plotOpts = Join[ context["regressionFunctionsPlotOptions"], plotOpts];
      ];

      res =
          Which[
            KeyExistsQ[context, "regressionFunctions"],
            Show[{
              listPlotFunc[data, listPlotOpts, Joined -> False, PlotRange -> All, ImageSize -> Medium, PlotTheme -> {"Default", "Frame"}],
              Plot[Evaluate[Through[Values[context["regressionFunctions"]][x]]], {x, Min[data[[All, 1]]], Max[data[[All, 1]]]},
                Evaluate[plotOpts],
                PerformanceGoal -> "Speed",
                PlotLegends -> Keys[context["regressionFunctions"]]
              ]
            }],

            True,
            listPlotFunc[data, listPlotOpts, Joined -> False, PlotRange -> All, ImageSize -> Medium, PlotTheme -> {"Default", "Frame"}]
          ];


      If[ TrueQ[OptionValue[QRMonPlot, "Echo"]],
        Echo[res, "Plot:"];
      ];

      QRMonUnit[res, Join[ context, <|"data" -> data|>] ]
    ];

QRMonPlot[__][__] := $QRMonFailure;


(**************************************************************)
(* DateListPlot                                               *)
(**************************************************************)

Clear[QRMonDateListPlot];

SyntaxInformation[QRMonDateListPlot] = { "ArgumentsPattern" -> {OptionsPattern[]} };

Options[QRMonDateListPlot] = Options[QRMonPlot];

QRMonDateListPlot[$QRMonFailure] := $QRMonFailure;

QRMonDateListPlot[xs_, context_Association] := QRMonPlot["DateListPlot" -> True][xs, context];

QRMonDateListPlot[opts : OptionsPattern[]][xs_, context_] := QRMonPlot["DateListPlot" -> True, opts][xs, context];

QRMonDateListPlot[__][__] := $QRMonFailure;


(**************************************************************)
(* Errors                                                     *)
(**************************************************************)

Clear[QRMonErrors];

SyntaxInformation[QRMonErrors] = { "ArgumentsPattern" -> {OptionsPattern[]} };

Options[QRMonErrors] = { "RelativeErrors" -> True };

QRMonErrors[$QRMonFailure] := $QRMonFailure;

QRMonErrors[xs_, context_Association] := QRMonErrors[][xs, context];

QRMonErrors[][xs_, context_] := QRMonErrors["RelativeErrors" -> True][xs, context];

QRMonErrors[opts : OptionsPattern[]][xs_, context_] :=
    Block[{res, relativeErrorsQ},

      relativeErrorsQ = TrueQ[OptionValue[QRMonErrors, "RelativeErrors"]];

      res =
          Association @
              KeyValueMap[
                Function[{k, f},
                  k -> Map[ Function[{p}, {p[[1]], (p[[2]] - f[p[[1]]]) / If[ !relativeErrorsQ || p[[2]] == 0, 1, p[[2]] ]}], context["data"] ]
                ],
                context["regressionFunctions"]
              ];

      QRMonUnit[res, context]
    ];

QRMonErrors[__][__] := $QRMonFailure;


(**************************************************************)
(* Error plots                                                *)
(**************************************************************)

Clear[QRMonErrorPlots];

SyntaxInformation[QRMonErrorPlots] = { "ArgumentsPattern" -> {OptionsPattern[]} };

Options[QRMonErrorPlots] = Join[ {"Echo" -> True, "DateListPlot" -> False, "RelativeErrors" -> True}, Options[ListPlot] ];

QRMonErrorPlots[$QRMonFailure] := $QRMonFailure;

QRMonErrorPlots[xs_, context_Association] := QRMonErrorPlots[][xs, context];

QRMonErrorPlots[opts : OptionsPattern[]][xs_, context_] :=
    Block[{res, listPlotFunc = ListPlot, listPlotOpts, relativeErrorsQ},

      listPlotFunc = If[ TrueQ[OptionValue[QRMonErrorPlots, "DateListPlot"]], DateListPlot, ListPlot ];

      listPlotOpts = Normal @ KeyTake[ {opts}, First /@ Options[listPlotFunc]];

      relativeErrorsQ = TrueQ[OptionValue[QRMonErrorPlots, "RelativeErrors"]];

      (* The error values can be reused from QRMonErrors, but it seems easier to just computed them here. *)
      res =
          KeyValueMap[
            Function[{k, f},
              k ->
                  listPlotFunc[
                    Map[Function[{p}, {p[[1]], (p[[2]] - f[p[[1]]]) / If[ !relativeErrorsQ || p[[2]] == 0, 1, p[[2]] ] }], context["data"] ],
                    listPlotOpts,
                    Joined -> False, PlotRange -> All, Filling -> Axis, Frame -> True, ImageSize -> Medium, PlotTheme -> {"Default", "Frame"}]
            ],
            context["regressionFunctions"]
          ];

      If[ TrueQ[OptionValue[QRMonErrorPlots, "Echo"]],
        Echo[res, If[relativeErrorsQ, "Relative error plots:", "Error plots:"]];
      ];

      QRMonUnit[res, context]
    ];

QRMonErrorPlots[__][__] := $QRMonFailure;


(**************************************************************)
(* Conditional distribution                                   *)
(**************************************************************)

Clear[CDFEstimate];
CDFEstimate[qFuncs_Association, t0_, intOrder : _Integer : 1] :=
    Interpolation[Transpose[{Through[Values[qFuncs][t0]], Keys[qFuncs]}], InterpolationOrder -> intOrder];

Clear[CDFPDFPlot];
CDFPDFPlot[t0_?NumberQ, qCDFInt_InterpolatingFunction, qs : {_?NumericQ..}, opts : OptionsPattern[]] :=
    Block[{},
      Plot[
        {qCDFInt[x], qCDFInt'[x]},
        {x, qCDFInt["Domain"][[1, 1]], qCDFInt["Domain"][[1, 2]]},
        opts, GridLines -> {None, qs}, PlotRange -> {0, 1}, Axes -> False, Frame -> True]
    ];

Clear[QRMonConditionalCDF];

SyntaxInformation[QRMonConditionalCDF] = { "ArgumentsPattern" -> {_} };

QRMonConditionalCDF[$QRMonFailure] := $QRMonFailure;

QRMonConditionalCDF[__][$QRMonFailure] := $QRMonFailure;

QRMonConditionalCDF[t0_?NumericQ][xs_, context_] := QRMonConditionalCDF[{t0}][xs, context];

QRMonConditionalCDF[ts : {_?NumericQ..}][xs_, context_] :=
    Block[{},
      Which[
        KeyExistsQ[context, "regressionFunctions"],
        QRMonUnit[ Association[ Map[ # -> CDFEstimate[ KeyDrop[context["regressionFunctions"], "mean"], # ] &, ts] ], context ],

        True,
        Echo["Cannot find regression quantiles.", "QRMonCDFApproximation:"];
        $QRMonFailure
      ]
    ];

QRMonConditionalCDF[args___][___] :=
    Block[{},
      Echo["The first argument is expected to be a number or a list of numbers.", "QRMonConditionalCDF:"];
      $QRMonFailure
    ];


(**************************************************************)
(* Conditional distributions plot                             *)
(**************************************************************)

Clear[QRMonConditionalCDFPlot];

SyntaxInformation[QRMonConditionalCDFPlot] = { "ArgumentsPattern" -> {OptionsPattern[]} };

Options[QRMonConditionalCDFPlot] := Join[ {"Echo" -> True, "QuantileGridLines" -> True}, Options[Plot] ];

QRMonConditionalCDFPlot[$QRMonFailure] := $QRMonFailure;

QRMonConditionalCDFPlot[__][$QRMonFailure] := $QRMonFailure;

QRMonConditionalCDFPlot[xs_, context_Association] := QRMonConditionalCDFPlot[ Options[QRMonConditionalCDFPlot] ][xs, context];

QRMonConditionalCDFPlot[ point_?NumericQ, opts : OptionsPattern[]][xs_, context_] :=
    QRMonConditionalCDFPlot[ {point}, opts][xs, context];

QRMonConditionalCDFPlot[ points : {_?NumericQ..}, opts : OptionsPattern[]][xs_, context_] :=
    Fold[ QRMonBind, QRMonUnit[xs, context], {QRMonConditionalCDF[points], QRMonConditionalCDFPlot[opts]}];

QRMonConditionalCDFPlot[ opts : OptionsPattern[] ][xs_, context_] :=
    Block[{funcs, res, plotOpts, quantileGridLinesQ},

      quantileGridLinesQ = TrueQ[ OptionValue[QRMonConditionalCDFPlot, "QuantileGridLines"] ];

      Which[

        MatchQ[xs, Association[(_?NumericQ -> _InterpolatingFunction) ..]],
        funcs = xs,

        True,
        Echo["The pipeline value is not an association of conditional CDF's.", "QRMonConditionalCDFPlot:"];
        Return[$QRMonFailure]
      ];

      If[ TrueQ[funcs === $QRMonFailure], Return[$QRMonFailure] ];

      plotOpts = FilterRules[ {opts}, Options[Plot]];

      (*  Epilog -> { MapThread[ Callout[{#1,0}, #2]&, { #["Coordinates"][[1]], Select[Keys[context["regressionFunctions"]], NumberQ]} ]} *)

      res =
          Association@
              KeyValueMap[#1 ->
                  Plot[#2[x], Prepend[First[#2["Domain"]], x],
                    Evaluate[plotOpts],
                    Evaluate[If[ quantileGridLinesQ, GridLines -> { #2["Coordinates"][[1]], None}, {}]],
                    PlotRange -> {All, All}, PlotLegends -> False,
                    PlotTheme -> {"Default", "Frame"},
                    PlotLabel -> Row[{"CDF at regressor value:", Spacer[2], #1}],
                    FrameLabel -> {"regressand", "Probability"},
                    ImageSize -> Small,
                    FrameTicks ->
                        {
                          {Automatic, Automatic},
                          {Automatic, If[ quantileGridLinesQ, MapThread[ {#1, #2}&, { #2["Coordinates"][[1]], Select[Keys[context["regressionFunctions"]], NumberQ]} ], Automatic]}
                        }
                  ] &, funcs];

      If[ TrueQ[OptionValue[QRMonConditionalCDFPlot, "Echo"]],
        Echo[ res, If[Length[res] == 1, "Conditional CDF:", "Conditional CDF's:"] ]
      ];

      QRMonUnit[res, context]
    ];

QRMonConditionalCDFPlot[__][__] :=
    Block[{},
      Echo[
        "Regressor points are expected as an argument and options. (Plot options or \"Echo\"->(True|False),  \"QuantileGridLines\"->(True|False).)",
        "QRMonConditionalCDFPlot:"
      ];
      $QRMonFailure
    ];


(**************************************************************)
(* Outlier finding (first)                                    *)
(**************************************************************)

Clear[QRMonOutliersFirst];

Options[QRMonOutliersFirst] := { "Knots" -> 12, "TopOutliersQuantile" -> 0.98, "BottomOutliersQuantile" -> 0.02 };

QRMonOutliersFirst[$QRMonFailure] := $QRMonFailure;

QRMonOutliersFirst[__][$QRMonFailure] := $QRMonFailure;

QRMonOutliersFirst[xs_, context_Association] := QRMonOutliersFirst[][xs, context];

QRMonOutliersFirst[opts : OptionsPattern[]][xs_, context_] :=
    Block[{knots, tq, bq, tfunc, bfunc, outliers, data},

      knots = OptionValue[ "Knots" ];
      Which[
        TrueQ[knots === Automatic],
        knots = 12,

        ! ( IntegerQ[knots] || VectorQ[knots, NumericQ]),
        Echo["The value of the options \"Knots\" is expected to be an integer or a list of numbers.", "QRMonOutliersFirst:"];
        Return[$QRMonFailure]
      ];

      tq = OptionValue[ "TopOutliersQuantile" ];
      bq = OptionValue[ "BottomOutliersQuantile" ];
      Which[
        ! ( NumberQ[tq] && 0 <= tq <= 1 && NumberQ[bq] && 0 <= bq <= 1  ),
        Echo["The values of the options \"TopOutliersQuantile\" and \"BottomOutliersQuantile\" are expected to be numbers between 0 and 1.", "QRMonOutliersFirst:"];
        Return[$QRMonFailure]
      ];

      data = QRMonTakeData[xs, context];

      If[ TrueQ[data === $QRMonFailure],
        Echo["Cannot find data.", "QRMonOutliersFirst:"];
        Return[$QRMonFailure]
      ];

      {bfunc, tfunc} = QuantileRegression[ data, knots, {bq, tq}, Method -> {LinearProgramming, Method -> "CLP"} ];

      outliers =
          <| "bottomOutliers" -> Select[data, bfunc[#[[1]]] >= #[[2]]&],
            "topOutliers" -> Select[data, tfunc[#[[1]]] <= #[[2]]&] |>;

      QRMonUnit[
        outliers,
        Join[context, <| "data" -> data, "outliers" -> outliers, "outlierRegressionFunctions" -> <| bq -> bfunc, tq -> tfunc|> |> ]
      ]
    ];

QRMonOutliersFirst[__][__] :=
    Block[{},
      Echo[StringJoin[ "Options are expected as arguments:", ToString[Options[QRMonOutliersFirst]], "."], "QRMonOutliersFirst:"];
      $QRMonFailure
    ];


(**************************************************************)
(* Outlier finding                                            *)
(**************************************************************)

Clear[QRMonOutliers];

SyntaxInformation[QRMonOutliers] = { "ArgumentsPattern" -> {} };

QRMonOutliers[$QRMonFailure] := $QRMonFailure;

QRMonOutliers[__][$QRMonFailure] := $QRMonFailure;

QRMonOutliers[xs_, context_Association] := QRMonOutliers[][xs, context];

QRMonOutliers[][xs_, context_] :=
    Block[{fn, tq, bq, tfunc, bfunc, outliers, data},

      If[ !( KeyExistsQ[context, "regressionFunctions"] && Length[KeyDrop[context["regressionFunctions"], "mean"]] > 0 ),
        Echo["Calculate (top and bottom) regression quantiles first.", "QRMonOutliers:"];
        Return[$QRMonFailure]
      ];

      data = QRMonTakeData[xs, context];

      If[ TrueQ[data === $QRMonFailure],
        Echo["Cannot find data.", "QRMonOutliers:"];
        Return[$QRMonFailure]
      ];

      fn = KeySort[KeyDrop[context["regressionFunctions"], "mean"]];

      {bq, tq} = Keys[fn][[{1, -1}]];

      {bfunc, tfunc} = Values[fn][[{1, -1}]];

      outliers =
          Which[
            Length[fn] == 1 && bq < 0.5,
            (* One regression quantile found for bottom outliers. *)
            <| "bottomOutliers" -> Select[data, bfunc[#[[1]]] >= #[[2]]&] |>,

            Length[fn] == 1 && tq > 0.5,
            (* One regression quantile found for top outliers. *)
            <| "topOutliers" -> Select[data, tfunc[#[[1]]] <= #[[2]]&] |>,

            True,
            <| "bottomOutliers" -> Select[data, bfunc[#[[1]]] >= #[[2]]&],
              "topOutliers" -> Select[data, tfunc[#[[1]]] <= #[[2]]&] |>
          ];

      QRMonUnit[
        outliers,
        Join[context, <| "data" -> data, "outliers" -> outliers, "outlierRegressionFunctions" -> <| bq -> bfunc, tq -> tfunc |> |> ]
      ]
    ];

QRMonOutliers[__][__] :=
    Block[{},
      Echo[StringJoin[ "No arguments and options are expected."], "QRMonOutliers:"];
      $QRMonFailure
    ];


(**************************************************************)
(* Outliers plot                                              *)
(**************************************************************)

Clear[QRMonOutliersPlot];

SyntaxInformation[QRMonOutliersPlot] = { "ArgumentsPattern" -> {OptionsPattern[]} };

Options[QRMonOutliersPlot] := Join[ {"Echo" -> True, "DateListPlot" -> False}, Options[ListPlot] ];

QRMonOutliersPlot[$QRMonFailure] := $QRMonFailure;

QRMonOutliersPlot[__][$QRMonFailure] := $QRMonFailure;

QRMonOutliersPlot[xs_, context_Association] := QRMonOutliersPlot[][xs, context];

QRMonOutliersPlot[opts : OptionsPattern[]][xs_, context_] :=
    Block[{unit, listPlotFunc = ListPlot, listPlotOpts, plotOpts, res},

      unit =
          If[ KeyExistsQ[context, "outliers"] && KeyExistsQ[context, "outlierRegressionFunctions"],
            QRMonUnit[ xs, context ],
            (*ELSE*)
            QRMonBind[ QRMonUnit[ xs, context ], QRMonOutliers ]
          ];

      If[ TrueQ[OptionValue[QRMonOutliersPlot, "DateListPlot"]], listPlotFunc = DateListPlot ];

      listPlotOpts = Normal @ KeyTake[ {opts}, First /@ Options[listPlotFunc]];
      plotOpts = Normal @ KeyTake[ {opts}, First /@ Options[Plot]];
      plotOpts = DeleteCases[plotOpts, HoldPattern[PlotStyle -> _] ];

      If[ KeyExistsQ[context, "dataPlotOptions"],
        listPlotOpts = Join[ context["dataPlotOptions"], listPlotOpts];
      ];

      If[ KeyExistsQ[context, "regressionFunctionsPlotOptions"],
        plotOpts = Join[ context["regressionFunctionsPlotOptions"], plotOpts];
      ];


      (* This can be improved: right now the regression quantiles are plotted over the outlier points. *)
      (* Also, there should be an option for not plotting the regression quantiles. *)

      res =
          Show[{

            listPlotFunc[Join[{#data}, Values[#outliers]] /. {} -> Nothing,
              listPlotOpts,
              PlotStyle -> {Gray, {PointSize[0.01], Lighter[Red]}, {PointSize[0.01], Lighter[Red]}},
              Joined -> False, PlotRange -> All, ImageSize -> Medium, PlotTheme -> {"Default", "Frame"}
            ],

            Plot[Evaluate@KeyValueMap[ Tooltip[#2[x], #1]&, #outlierRegressionFunctions], Prepend[MinMax[#data[[All, 1]]], x],
              Evaluate[plotOpts],
              PlotStyle -> {Opacity[0.1], GrayLevel[0.9]},
              PerformanceGoal -> "Speed"
              (*PlotRange -> {MinMax[#data[[All,1]]], MinMax[#data[[All,2]]]}*)
            ]

          }] &[ QRMonBind[ unit, QRMonTakeContext ] ];

      If[ TrueQ[OptionValue[QRMonOutliersPlot, "Echo"]],
        Echo[res, "Outliers plot:"]
      ];

      QRMonUnit[ res, QRMonBind[ unit, QRMonTakeContext ] ]
    ];


QRMonOutliersPlot[___][__] := $QRMonFailure;


(**************************************************************)
(* Pick path points                                           *)
(**************************************************************)

Clear[QRMonPickPathPoints];

SyntaxInformation[QRMonPickPathPoints] = { "ArgumentsPattern" -> {_, OptionsPattern[]} };

Options[QRMonPickPathPoints] = { "PickAboveThreshold" -> False, "RelativeErrors" -> False };

QRMonPickPathPoints[$QRMonFailure] := $QRMonFailure;

QRMonPickPathPoints[__][$QRMonFailure] := $QRMonFailure;

QRMonPickPathPoints[threshold_?NumberQ, opts : OptionsPattern[] ][xs_, context_] :=
    Block[{data, qFuncs, res, criteriaFunc = LessEqual},

      data = QRMonTakeData[xs, context];

      If[ !KeyExistsQ[context, "regressionFunctions"],
        Echo["Cannot find regression functions.", "QRMonPickPathPoints:"];
        Return[$QRMonFailure]
      ];

      qFuncs = context["regressionFunctions"];

      If[ TrueQ[OptionValue[QRMonPickPathPoints, "PickAboveThreshold"]],
        criteriaFunc = Greater;
      ];

      If[ TrueQ[OptionValue[QRMonPickPathPoints, "RelativeErrors"]],
        res = Map[ Function[{qf}, Select[data, criteriaFunc[ Abs[ (qf[#[[1]]] - #[[2]]) / #[[2]] ], threshold] &]], qFuncs ],
        (*ELSE*)
        res = Map[ Function[{qf}, Select[data, criteriaFunc[ Abs[qf[#[[1]]] - #[[2]]], threshold] &]], qFuncs ]
      ];

      QRMonUnit[res, context]
    ] /; threshold >= 0;

QRMonPickPathPoints[___][__] :=
    Block[{},
      Echo["The first argument is expected to be a non-negative number.", "QRMonPickPathPoints:"];
      $QRMonFailure
    ];


(**************************************************************)
(* Separate points by regression quantiles                    *)
(**************************************************************)

Clear[QRMonSeparate];

SyntaxInformation[QRMonSeparate] = { "ArgumentsPattern" -> {_., OptionsPattern[]} };

Options[QRMonSeparate] = { "Cumulative" -> True, "Fractions" -> False };

QRMonSeparate[$QRMonFailure] := $QRMonFailure;

QRMonSeparate[__][$QRMonFailure] := $QRMonFailure;

QRMonSeparate[xs_, context_Association] := QRMonSeparate[][xs, context];

QRMonSeparate[][xs_, context_Association] := QRMonSeparate[Automatic][xs, context];

QRMonSeparate[opts : OptionsPattern[]][xs_, context_Association] := QRMonSeparate[Automatic, opts][xs, context];

QRMonSeparate[dataArg_, opts : OptionsPattern[] ][xs_, context_] :=
    Block[{data, indGroups, pointGroups, cumulativeQ, fractionsQ},

      cumulativeQ = TrueQ[ OptionValue[ QRMonSeparate, "Cumulative" ] ];
      fractionsQ = TrueQ[ OptionValue[ QRMonSeparate, "Fractions" ] ];

      If[ TrueQ[dataArg === Automatic],
        data = Fold[ QRMonBind, QRMonUnit[xs, context], {QRMonGetData, QRMonTakeValue}],
        (* ELSE *)
        data = Fold[ QRMonBind, QRMonUnit[dataArg], {QRMonGetData, QRMonTakeValue}]
      ];

      If[ TrueQ[data === $QRMonFailure ],
        Return[$QRMonFailure]
      ];

      If[ !KeyExistsQ[context, "regressionFunctions"],
        Echo["Cannot find regression functions.", "QRMonSeparate:"];
        Return[$QRMonFailure]
      ];

      (* This has to be optimized. Currently is O[ Length[data] * Length[regressionFunctions] ] . Can be at least halved. *)
      If[ cumulativeQ,

        pointGroups =
            Association @
                KeyValueMap[
                  Function[{k, f}, k -> Select[ data, #[[2]] <= f[#[[1]]] & ] ],
                  context["regressionFunctions"]
                ],

        (*ELSE*)
        (* Find the indices corresponding to data points under each regression function. *)
        indGroups =
            Association @
                KeyValueMap[
                  Function[{k, f}, k -> Select[ Range[Length[data]], data[[#, 2]] <= f[data[[#, 1]]] & ] ],
                  KeyDrop[ context["regressionFunctions"], "mean" ]
                ];

        (* Find complements of the indices that belong to pairs of consecutive quantiles. *)
        indGroups =
            Join[
              KeyTake[ indGroups, First[Sort[Keys[indGroups]]] ],
              Association @
                  Map[
                    Function[{k}, k[[2]] -> Complement[ indGroups[k[[2]]], indGroups[k[[1]]] ] ],
                    Partition[ Sort[Keys[indGroups]], 2, 1]
                  ]
            ];

        pointGroups = Map[ data[[#]]&, indGroups]
      ];

      If[ fractionsQ,
        pointGroups = Map[ Length[#] / Length[data] &, pointGroups ];
      ];

      QRMonUnit[ pointGroups, context ]
    ];

QRMonSeparate[___][__] := $QRMonFailure;


Clear[QRMonSeparateToFractions];

SyntaxInformation[QRMonSeparateToFractions] = { "ArgumentsPattern" -> {_., OptionsPattern[]} };

Options[QRMonSeparateToFractions] = {"Cumulative" -> False};

QRMonSeparateToFractions[$QRMonFailure] := $QRMonFailure;

QRMonSeparateToFractions[__][$QRMonFailure] := $QRMonFailure;

QRMonSeparateToFractions[xs_, context_Association] := QRMonSeparateToFractions[][xs, context];

QRMonSeparateToFractions[][xs_, context_Association] := QRMonSeparateToFractions[Automatic][xs, context];

QRMonSeparateToFractions[opts : OptionsPattern[]][xs_, context_Association] := QRMonSeparateToFractions[Automatic, opts][xs, context];

QRMonSeparateToFractions[dataArg_, opts : OptionsPattern[] ][xs_, context_] :=
    Block[{cumulativeQ},

      cumulativeQ = TrueQ[ OptionValue[ QRMonSeparateToFractions, "Cumulative" ] ];

      QRMonSeparate[ dataArg, "Fractions" -> True, "Cumulative" -> cumulativeQ ][xs, context]
    ];

QRMonSeparateToFractions[___][__] := $QRMonFailure;


(**************************************************************)
(* Bands sequential representation                            *)
(**************************************************************)

Clear[FindIntervalFunc];
FindIntervalFunc[qBoundaries : {_?NumericQ ...}] :=
    Block[{XXX, t = Partition[Join[{- Infinity}, qBoundaries, {Infinity}], 2, 1]},
      Function[
        Evaluate[
          Piecewise[
            MapThread[{#2, #1[[1]] < XXX <= #1[[2]]} &, {t, Range[1, Length[t]]}]
          ] /. {XXX -> #}
        ]
      ]
    ];

Clear[FindQRRange];
FindQRRange[{x_, y_}, funcs_List] :=
    Block[{qfs, pfunc},
      qfs = Through[funcs[x]];
      pfunc = FindIntervalFunc[qfs];
      pfunc[y]
    ];

Clear[QRMonBandsSequence];

SyntaxInformation[QRMonBandsSequence] = { "ArgumentsPattern" -> {} };

QRMonBandsSequence[$QRMonFailure] := $QRMonFailure;

QRMonBandsSequence[___][$QRMonFailure] := $QRMonFailure;

QRMonBandsSequence[xs_, context_Association ] := QRMonBandsSequence[][xs, context];

QRMonBandsSequence[][xs_, context_] :=
    Block[{qstates},

      Which[

        !KeyExistsQ[context, "data"],
        Echo["Cannot find data.", "QRMonBandsSequence:"];
        $QRMonFailure,

        !KeyExistsQ[context, "regressionFunctions"],
        Echo["Compute the regression quantiles first.", "QRMonBandsSequence:"];
        $QRMonFailure,

        True,
        qstates = FindQRRange[ #, Values[context["regressionFunctions"]] ]& /@ QRMonBind[ QRMonGetData[xs, context], QRMonTakeValue ];
        QRMonUnit[ qstates, context ]
      ]

    ];

QRMonBandsSequence[__][__] :=
    Block[{},
      Echo[ "No arguments are expected.", "QRMonBandsSequence:"];
      $QRMonFailure
    ];


(**************************************************************)
(* Grid sequential representation                             *)
(**************************************************************)

Clear[QRMonGridSequence];

SyntaxInformation[QRMonGridSequence] = { "ArgumentsPattern" -> { _. } };

QRMonGridSequence[$QRMonFailure] := $QRMonFailure;

QRMonGridSequence[___][$QRMonFailure] := $QRMonFailure;

QRMonGridSequence[xs_, context_Association ] := QRMonGridSequence[][xs, context];

QRMonGridSequence[][xs_, context_] := QRMonGridSequence[Automatic][xs, context];

QRMonGridSequence[Automatic][xs_, context_] :=
    Block[{data, qvals},

      data = Fold[ QRMonBind, QRMonUnit[xs, context], { QRMonGetData, QRMonTakeValue }];

      Which[

        TrueQ[data === $QRMonFailure],
        Echo["Cannot find data.", "QRMonGridSequence:"];
        $QRMonFailure,

        KeyExistsQ[context, "regressionFunctions"],
        qvals = Quantile[ data[[All, 2]], Keys[context["regressionFunctions"]] ];
        QRMonGridSequence[ qvals ][xs, Join[context, <|"data" -> data|> ]],

        True,
        Echo["Cannot find quantiles for the values mapping with Automatic grid argument.", "QRMonGridSequence"];
        $QRMonFailure
      ]
    ];

QRMonGridSequence[gridNCells_Integer][xs_, context_] :=
    Block[{data, rvals},

      data = Fold[ QRMonBind, QRMonUnit[xs, context], { QRMonGetData, QRMonTakeValue }];

      Which[

        gridNCells < 1,
        Echo["An integer first argument is expected to be positive.", "QRMonGridSequence"];
        $QRMonFailure,

        ! TrueQ[data === $QRMonFailure],
        rvals = Rescale[Range[1, gridNCells], {1, gridNCells}, MinMax[data[[All, 2]]]];
        QRMonGridSequence[ rvals ][xs, Join[context, <|"data" -> data|> ]],

        True,
        Echo["Cannot find data.", "QRMonGridSequence"];
        $QRMonFailure
      ]
    ];

QRMonGridSequence[grid : {_?NumericQ..}][xs_, context_] :=
    Block[{stFunc, states, data},

      data = Fold[ QRMonBind, QRMonUnit[xs, context], { QRMonGetData, QRMonTakeValue }];

      Which[

        TrueQ[data === $QRMonFailure],
        Echo["Cannot find data.", "QRMonGridSequence:"];
        $QRMonFailure,

        True,
        stFunc = FindIntervalFunc[grid];
        states = stFunc /@ data[[All, 2]];
        QRMonUnit[ states, context ]
      ]

    ];

QRMonGridSequence[___][__] :=
    Block[{},
      Echo[ "The first argument is expected to be Automatic, an integer, or a list of numbers.", "QRMonGridSequence:"];
      $QRMonFailure
    ];


(**************************************************************)
(* MovingAverage                                              *)
(**************************************************************)

Clear[QRMonMovingAverage];

SyntaxInformation[QRMonMovingAverage] = { "ArgumentsPattern" -> {_} };

QRMonMovingAverage[$QRMonFailure] := $QRMonFailure;

QRMonMovingAverage[___][$QRMonFailure] := $QRMonFailure;

QRMonMovingAverage[xs_, context_Association ] := $QRMonFailure;

QRMonMovingAverage[n : ( _Integer | {_?NumericQ..} ) ][xs_, context_] :=
    Fold[
      QRMonBind,
      QRMonUnit[xs, context],
      { QRMonGetData, (QRMonUnit[MovingAverage[#1, n], #2] &) }
    ];

QRMonMovingAverage[___][__] := $QRMonFailure;


(**************************************************************)
(* MovingMedian                                               *)
(**************************************************************)

Clear[QRMonMovingMedian];

SyntaxInformation[QRMonMovingMedian] = { "ArgumentsPattern" -> {_} };

QRMonMovingMedian[$QRMonFailure] := $QRMonFailure;

QRMonMovingMedian[___][$QRMonFailure] := $QRMonFailure;

QRMonMovingMedian[xs_, context_Association ] := $QRMonFailure;

QRMonMovingMedian[n : ( _Integer | {_?NumericQ..} ) ][xs_, context_] :=
    Fold[
      QRMonBind,
      QRMonUnit[xs, context],
      { QRMonGetData, (QRMonUnit[MovingMedian[#1, n], #2] &) }
    ];

QRMonMovingMedian[___][__] := $QRMonFailure;


(**************************************************************)
(* Moving map                                                 *)
(**************************************************************)

Clear[QRMonMovingMap];

SyntaxInformation[QRMonMovingMap] = { "ArgumentsPattern" -> {_, _} };

QRMonMovingMap[$QRMonFailure] := $QRMonFailure;

QRMonMovingMap[___][$QRMonFailure] := $QRMonFailure;

QRMonMovingMap[xs_, context_Association ] := $QRMonFailure;

QRMonMovingMap[f_, wspec__ ][xs_, context_] :=
    Fold[
      QRMonBind,
      QRMonUnit[xs, context],
      { QRMonGetData,
        (QRMonUnit[MovingMap[f, #1, wspec], #2] &),
        (QRMonWhen[!(MatrixQ[#] || VectorQ[#])&, QRMonFail])
      }
    ];

QRMonMovingMap[___][__] := $QRMonFailure;


(**************************************************************)
(* Simulate                                                   *)
(**************************************************************)

Clear[QRMonSimulate];

SyntaxInformation[QRMonSimulate] = { "ArgumentsPattern" -> { _, OptionsPattern[] } };

QRMonSimulate[$QRMonFailure] := $QRMonFailure;

QRMonSimulate[___][$QRMonFailure] := $QRMonFailure;

QRMonSimulate[xs_, context_Association ] := $QRMonFailure;

QRMonSimulate[nTimePoints_Integer, opts : OptionsPattern[]][xs_, context_] :=
    Block[{r, tPoints},

      r = QRMonBind[ QRMonUnit[xs, context], QRMonTakeData ];
      r = MinMax @ r[[All, 1]];

      tPoints = Range[ r[[1]], r[[2]], (r[[2]] - r[[1]]) / (nTimePoints - 1) ];

      QRMonSimulate[tPoints, opts][xs, context]
    ];

QRMonSimulate[timePoints : {_?NumericQ..}, opts : OptionsPattern[]][xs_, context_] :=
    Block[{qValues, qs, tValues, enoughQuantiles },

      If[ ! ( KeyExistsQ[context, "regressionFunctions"] && Length[KeyDrop[context["regressionFunctions"], "mean"]] > 1),
        Echo["Compute two or more regression quantiles first.", "QRMonSimulate:"];
        Return[$QRMonFailure]
      ];

      qValues =
          Fold[
            QRMonBind,
            QRMonUnit[xs, context],
            { QRMonEvaluate[timePoints],
              QRMonTakeValue }];

      qValues = KeySort @ qValues;
      qs = Keys[qValues];
      qValues = Transpose[Values[qValues]];

      tValues =
          Flatten@Map[RandomReal[RandomChoice[#], 1] &, Differences[qs] -> Partition[#, 2, 1] & /@ qValues];

      QRMonUnit[ Transpose[{timePoints, tValues}], context]
    ];

QRMonSimulate[___][__] :=
    Block[{},
      Echo["The first argument is expected to be an integer or a list of numbers.", "QRMonSimulate:"];
      $QRMonFailure
    ];


(**************************************************************)
(* Local extrema                                              *)
(**************************************************************)

(*
   The function QRFindExtrema was originally defined in the package:

     https://github.com/antononcube/MathematicaForPrediction/blob/master/Applications/QuantileRegressionForLocalExtrema.m

   Instead of importing that package I think it is better to define QRMonFindExtrema as a monad function that uses
   previously computed regression quantiles.
*)

Clear[QRMonLocalExtrema];

SyntaxInformation[QRMonLocalExtrema] = { "ArgumentsPattern" -> { OptionsPattern[] } };

Options[QRMonLocalExtrema] = { "NearestWithOutliers" -> False, "NumberOfProximityPoints" -> 50 };

QRMonLocalExtrema[$QRMonFailure] = $QRMonFailure;

QRMonLocalExtrema[xs_, context_Association] = QRMonLocalExtrema[][xs, context];

QRMonLocalExtrema[ opts : OptionsPattern[] ][$QRMonFailure] := $QRMonFailure;

QRMonLocalExtrema[ opts : OptionsPattern[] ][xs_, context_] :=
    Module[{nearestByOutliersQ, numberOfProximityPoints, data, fn, extrema1, extrema2, minima, maxima, x, signs1, signs2, extremaPoints, nfMax, nfMin },

      nearestByOutliersQ = TrueQ[OptionValue[QRMonLocalExtrema, "NearestWithOutliers" ]];
      numberOfProximityPoints = OptionValue[QRMonLocalExtrema, "NumberOfProximityPoints" ];

      If[ ! IntegerQ[numberOfProximityPoints],
        Echo[ "The value of the option \"NumberOfProximityPoints\" is expected to be an integer.",
          "QRMonLocalExtrema:"];
        Return[$QRMonFailure];
      ];

      (* Step 1 *)
      If[ !( KeyExistsQ[context, "regressionFunctions"] && Length[KeyDrop[context["regressionFunctions"], "mean"]] > 0 ),
        Echo["Calculate (top and bottom) regression quantiles first.", "QRMonLocalExtrema:"];
        Return[$QRMonFailure]
      ];

      fn = KeySort[KeyDrop[context["regressionFunctions"], "mean"]];

      fn = {fn[[1]], fn[[-1]]};

      data = QRMonTakeData[xs, context];

      (* Step 2 *)
      extrema1 = Reduce[fn[[1]]'[x] == 0, x, Reals];
      extrema1 = Cases[{ToRules[extrema1]}, _Rule, Infinity ];
      signs1 = Sign[fn[[1]]''[#] & /@ extrema1[[All, 2]]];
      extrema2 = Reduce[fn[[-1]]'[x] == 0, x, Reals];
      extrema2 = Cases[{ToRules[extrema2]}, _Rule, Infinity ];
      signs2 = Sign[fn[[-1]]''[#] & /@ extrema2[[All, 2]]];

      (* Step 3 *)
      minima =
          Map[{#, fn[[1]][#]} &,
            Pick[extrema1[[All, 2]], # > 0 & /@ signs1]];
      maxima =
          Map[{#, fn[[-1]][#]} &,
            Pick[extrema2[[All, 2]], # < 0 & /@ signs2]];

      If[ nearestByOutliersQ,
        nfMin = Nearest[ Select[ data, #[[2]] <= fn[[1]][#[[1]]]& ] ];
        nfMax = Nearest[ Select[ data, #[[2]] >= fn[[-1]][#[[1]]]& ] ];,
        (* ELSE *)
        nfMin = Nearest[data];
        nfMax = nfMin;
      ];

      extremaPoints = {
        Map[ First@SortBy[ nfMin[#, numberOfProximityPoints], #[[-1]]& ]&, minima ],
        Map[ First@SortBy[ nfMax[#, numberOfProximityPoints], -#[[-1]]& ]&, maxima ]
      };

      QRMonUnit[ Union /@ AssociationThread[ { "localMinima", "localMaxima" }, extremaPoints ], context]
    ];

QRMonLocalExtrema[___][__] :=
    Block[{},
      Echo["No arguments are expected. The options are \"NearestWithOutliers\" -> (True|False), \"NumberOfProximityPoints\" -> _Integer .",
        "QRMonLocalExtrema:"];
      $QRMonFailure
    ];

Clear[QRMonFindLocalExtrema];
QRMonFindLocalExtrema = QRMonLocalExtrema;


(**************************************************************)
(* Chow Test                                                  *)
(**************************************************************)

(*
   The function QRFindExtrema was originally defined in the package:

      https://github.com/antononcube/MathematicaForPrediction/blob/master/Misc/ChowTestStatistic.m .
*)

Clear[ChowTestStatistic];

SyntaxInformation[ChowTestStatistic] = { "ArgumentsPattern" -> { _, _, ___, ___ } };

ChowTestStatistic::empfuncs = "A non empty list of functions is expected.";
ChowTestStatistic::novar = "The specified variable is not a symbol.";
ChowTestStatistic::nofuncsvar = "The specified variable should be found in the functions list.";
ChowTestStatistic::empdata = "The split point `1` produced an empty split dataset.";
ChowTestStatistic::expargs = "The implemented signatures are:\n\
ChowTestStatistic[data : {{_?NumberQ, _?NumberQ} ..}, splitPoint_?NumberQ, funcs_List: {1, x}, var_: x],\n\
ChowTestStatistic[data : {{_?NumberQ, _?NumberQ} ..}, splitPoints : {_?NumberQ ..}, funcs_List: {1, x}, var_: x], and\n\
ChowTestStatistic[data1 : {{_?NumberQ, _?NumberQ} ..}, data2 : {{_?NumberQ, _?NumberQ} ..}, funcs_List: {1, x}, var_: x].";

ChowTestStatistic[data : {{_?NumberQ, _?NumberQ} ..}, splitPoints : {_?NumberQ ..}, funcs_List : {1, x}, var_ : x] :=
    Block[{data1, data2, S, S1, S2, k, ff, res},

      If[Length[funcs] == 0,
        Message[ChowTestStatistic::empfuncs];
        Return[$Failed]
      ];

      If[! Developer`SymbolQ[var],
        Message[ChowTestStatistic::novar];
        Return[$Failed]
      ];

      If[FreeQ[funcs, var],
        Message[ChowTestStatistic::nofuncsvar];
        Return[$Failed]
      ];

      k = Count[Developer`SymbolQ /@ funcs, True];

      If[ $VersionNumber >= 12,
        res = Fit[data, funcs, var, "FitResiduals"],
        (* ELSE *)
        ff = Fit[data, funcs, var];
        res = MapThread[(ff /. var -> #1) - #2 &, Transpose[data] ]
      ];

      S = res.res;

      Map[
        Function[{sp},

          data1 = Select[data, #[[1]] < sp &];
          data2 = Select[data, #[[1]] >= sp &];

          If[ Length[data1] == 0 || Length[data2] == 0,

            Message[ChowTestStatistic::empdata, sp];
            $Failed,

            (* ELSE *)

            {S1, S2} =
                Map[
                  Function[{d},
                    res = Fit[d, funcs, var, "FitResiduals"];
                    res.res
                  ],
                  {data1, data2}];

            {sp, ((S - (S1 + S2)) / k) / ((S1 + S2) / (Length[data1] + Length[data2] - 2 k)) }
          ]

        ],
        splitPoints
      ]

    ];


(**************************************************************)
(* QRMonChowTestStatistic                                     *)
(**************************************************************)

Clear[QRMonChowTestStatistic];

SyntaxInformation[QRMonChowTestStatistic] = { "ArgumentsPattern" -> { _, ___, ___ } };

QRMonChowTestStatistic[$QRMonFailure] := $QRMonFailure;

QRMonChowTestStatistic[xs_, context_Association] := QRMonChowTestStatistic[][xs, context];

QRMonChowTestStatistic[][xs_, context_] := QRMonChowTestStatistic[Automatic, Automatic, Automatic][xs, context];

QRMonChowTestStatistic[splitPoints_][xs_, context_] := QRMonChowTestStatistic[splitPoints, Automatic, Automatic][xs, context];

QRMonChowTestStatistic[splitPoints : (Automatic | {_?NumericQ ..} | _?NumericQ), funcs : ( Automatic | _List), var_ : Automatic][xs_, context_] :=
    Block[{data, localSplitPoints = splitPoints, localFuncs = funcs, localVar = var, x, ctStats},

      data = QRMonBind[QRMonGetData[xs, context], QRMonTakeValue];

      If[ TrueQ[localFuncs === Automatic],
        localFuncs = {1, x};
        localVar = x
      ];

      If[Length[localFuncs] == 0,
        Echo["A non empty list of functions is expected.", "QRMonChowTestStatistic:"];
        Return[$QRMonFailure]
      ];

      If[TrueQ[localSplitPoints === Automatic],
        localSplitPoints = (Min[data[[All, 1]]] + Accumulate[Differences[Sort[data[[All, 1]]]]]);
      ];

      If[TrueQ[NumericQ[localSplitPoints]],
        localSplitPoints = {localSplitPoints};
      ];

      If[ TrueQ[localVar === Automatic],
        localVar =
            With[{globalQ = Context@# === "Global`" &},
              DeleteDuplicates@Cases[localFuncs, _Symbol?globalQ, Infinity]
            ],
        (* ELSE *)
        localVar = {localVar}
      ];

      Which[
        Length[localVar] == 0,
        Echo["No variable was found in the list of functions.", "QRMonChowTestStatistic:"];
        Return[$QRMonFailure],

        Length[localVar] > 1,
        Echo["More than one variable was found in the list of functions.", "QRMonChowTestStatistic:"];
        Return[$QRMonFailure],

        True,
        localVar = First[localVar]
      ];

      ctStats = ChowTestStatistic[data, localSplitPoints, localFuncs, localVar];

      If[ TrueQ[ctStats === $Failed] || !FreeQ[ctStats, $Failed],
        Return[$QRMonFailure]
      ];

      QRMonUnit[ctStats, context]
    ];

QRMonChowTestStatistic[args___][__] :=
    Block[{},
      Echo["The first argument is expected to be a specification of split points, (Automatic|{_?NumericQ..}|_?NumericQ). " <>
          "The second argument is expected to be Automatic or a list of functions. " <>
          "The third argument is expected to be Automatic or a variable symbol.",
        "QRMonChowTestStatistic:"];
      $QRMonFailure;
    ];

(*=========================================================*)
(* Summary Box                                             *)
(*=========================================================*)

QRMon /: MakeBoxes[obj_QRMon, form : StandardForm] :=
    Block[{ctx = QRMonBind[obj, QRMonTakeContext]},
      BoxForm`ArrangeSummaryBox[
        QRMon, obj,
        None, (*the next argument is the always visible properties*)
        If[KeyExistsQ[ctx, "data"],
          {
            BoxForm`SummaryItem@{"Data dimensions: ", Dimensions[QRMonBind[obj, QRMonTakeData]]}
          },
          (*ELSE*)
          {BoxForm`SummaryItem@{"No data"}}
        ],
        {
          If[KeyExistsQ[ctx, "regressionFunctions"],
            BoxForm`SummaryItem@{"Number of regression quantiles: ", Length[ctx["regressionFunctions"]]},
            Nothing
          ],
          BoxForm`SummaryItem@{"Value: ", Short @ QRMonBind[obj, QRMonTakeValue]}
        },
        form]
    ];

End[]; (* `Private` *)

EndPackage[]