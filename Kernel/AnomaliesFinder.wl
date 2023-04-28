
(* :Title: MonadicAnomaliesFinder *)
(* :Context: MonadicAnomaliesFinder` *)
(* :Author: Anton Antonov *)
(* :Date: 2019-09-13 *)
(* Created with the Wolfram Language Plugin for IntelliJ, see http://wlplugin.halirutan.de/ . *)

(* :Package Version: 0.5 *)
(* :Mathematica Version: 12.0 *)
(* :Copyright: (c) 2019 Anton Antonov *)
(* :Keywords: Quantile Regression, Anomalies, Outliers *)
(* :Discussion:

   # In brief

   This package provides functions to for the Quantile Regression Monad package (QRMon):

     https://github.com/antononcube/MathematicaForPrediction/blob/master/MonadicProgramming/MonadicQuantileRegression.m .

   Here is an example usage:

      ts = FinancialData[Entity["Financial", "^SPX"], {{2015, 1, 1}, Date[]}];

      qrObj =
        QRMonUnit[ts]⟹
          QRMonEchoDataSummary⟹
          QRMonQuantileRegression[100, 0.5]⟹
          QRMonDateListPlot⟹
          QRMonFindAnomaliesByResiduals["RelativeErrors" -> False, "OutlierIdentifier" -> SPLUSQuartileIdentifierParameters]⟹
          QRMonEchoFunctionValue[RecordsSummary];

      DateListPlot[{ts, qrObj⟹QRMonTakeValue}, Joined -> {True, False}, PlotStyle -> {Gray, {Red, PointSize[0.01]}}]

   # Future plans

   It would be nice the data and anomalies plot to be part of the monadic pipeline.

   Anton Antonov
   Windermere, Florida, USA
   2019-09-13

*)


(**************************************************************)
(* Package definition                                         *)
(**************************************************************)

BeginPackage["AntonAntonov`MonadicQuantileRegression`AnomaliesFinder`"];

(*QRMonFindAnomaliesByResiduals::usage = "QRMonFindAnomaliesByResiduals[ opts:OptionsPattern[] ] \*)
(*finds anomalies by finding outliers in fit errors.*)

Begin["`Private`"];

Needs["AntonAntonov`MonadicQuantileRegression`"];
Needs["AntonAntonov`OutlierIdentifiers`"];


(**************************************************************)
(* Find point anomalies using approximation residuals         *)
(**************************************************************)

Clear[QRMonFindAnomaliesByResiduals];

SyntaxInformation[QRMonFindAnomaliesByResiduals] = { "ArgumentsPattern" -> { OptionsPattern[] } };

Options[QRMonFindAnomaliesByResiduals] = { "Threshold" -> None, "OutlierIdentifier" -> HampelIdentifierParameters, "RelativeErrors" -> False };

QRMonFindAnomaliesByResiduals[$QRMonFailure] := $QRMonFailure;

QRMonFindAnomaliesByResiduals[xs_, context_Association] := QRMonFindAnomaliesByResiduals[ Options[QRMonFindAnomaliesByResiduals] ][xs, context];

QRMonFindAnomaliesByResiduals[ opts : OptionsPattern[] ][xs_, context_Association] :=
    Block[{ threshold, relativeErrorsQ, outlierFunc, errs, outPos, outliers },

      threshold = OptionValue[ QRMonFindAnomaliesByResiduals, "Threshold" ];
      relativeErrorsQ = TrueQ[ OptionValue[ QRMonFindAnomaliesByResiduals, "RelativeErrors" ] ];
      outlierFunc = OptionValue[ QRMonFindAnomaliesByResiduals, "OutlierIdentifier" ];

      Which[
        NumberQ[threshold],
        outliers =
            Fold[ QRMonBind,
              QRMonUnit[xs, context],
              {
                QRMonPickPathPoints[ threshold, "PickAboveThreshold" -> True, "RelativeErrors" -> relativeErrorsQ ],
                QRMonTakeValue
              }];

        If[ TrueQ[outliers === $QRMonFailure], Return[$QRMonFailure] ];

        outliers = outliers[[1]],

        TrueQ[ outlierFunc =!= None],
        errs =
            Fold[ QRMonBind,
              QRMonUnit[xs, context],
              {
                QRMonErrors[ "RelativeErrors" -> relativeErrorsQ],
                QRMonTakeValue
              }];

        If[ TrueQ[outliers === $QRMonFailure], Return[$QRMonFailure] ];

        outPos = OutlierPosition[ Abs[errs[[1, All, 2]]], TopOutliers @* outlierFunc ];

        outliers = QRMonBind[ QRMonUnit[xs, context], QRMonTakeData];
        outliers = outliers[[outPos]],

        True,
        Return[ QRMonFindAnomaliesByResiduals[ "not good" ][xs, context] ]
      ];

      QRMonUnit[ outliers, context ]
    ];

QRMonFindAnomaliesByResiduals[___][xs_, context_Association] :=
    Block[{},
      Echo[
        "The expected signature is QRMonFindAnomaliesByResiduals[ opts:OptionsPattern[] ]." <>
            " The option \"Threshold\" is expected to be None or a number (an errors threshold.)." <>
            " The option \"OutlierIdentifier\" is expected to be None" <>
            " or a function that give a list of lower and upper thresholds when applied to a list of numbers (errors absolute values.)",
        "QRMonFindAnomaliesByResiduals:"
      ];
      $QRMonFailure
    ];

End[]; (* `Private` *)

EndPackage[]