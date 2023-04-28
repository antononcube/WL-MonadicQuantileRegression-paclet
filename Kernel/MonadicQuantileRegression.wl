BeginPackage["AntonAntonov`MonadicQuantileRegression`"];


$QRMonFailure::usage = "Failure symbol for the monad QRMon.";

QRMonGetData::usage = "Get time series path data.";

QRMonTakeData::usage = "Takes the time series path data.";

QRMonEchoDataSummary::usage = "QRMonEchoDataSummary[] echoes a summary of the data.";

QRMonDeleteMissing::usage = "QRMonDeleteMissing[] deletes records with missing data.";

QRMonRescale::usage = "QRMonRescale[Axes->{_,_}] rescales the data.";

QRMonLeastSquaresFit::usage = "QRMonLeastSquaresFit[ funcs : ( _List | _Integer ) ] does a Linear regression fit \
for the data in the pipeline or the context using specified functions to fit.";

QRMonFit::usage = "Same as QRMonLinearRegressionFit.";

QRMonQuantileRegression::usage = "QRMonQuantileRegression[knots: ( _Integer | _?VectorQ ), probs_?VectorQ, opts___] \
does Quantile Regression for the data in the pipeline or the context.";

QRMonRegression::usage = "Same as QRMonQuantileRegression.";

QRMonQuantileRegressionFit::usage = "QRMonLinearRegressionFit[ funcs : ( _List | _Integer), probs_?VectorQ ] does a \
Quantile regression fit using specified functions to fit and probabilities. An integer funcs specifies \
a ChebyshevT polynomials basis.";

QRMonRegressionFit::usage = "Same as QRMonQuantileRegressionFit.";

QRMonNetRegression::usage = "Regression using a neural network.";

QRMonEvaluate::usage = "QRMonEvaluate[points_?VectorQ] evaluates the regression functions over a number \
or a list of numbers.";

QRMonPlot::usage = "QRMonPlot[opts___] plots the data points or the data points together with the found regression curves.";

QRMonDateListPlot::usage = "QRMonDateListPlot[opts___] plots the data points or the data points together with the found regression curves.";

QRMonErrors::usage = "QRMonErrors[opts___] finds relative or absolute approximation errors for each regression quantile.";

QRMonErrorPlots::usage = "QRMonErrorPlots[opts___] plots relative approximation errors for each regression quantile.";

QRMonConditionalCDF::usage = "QRMonConditionalCDF[points_?VectorQ] finds conditional CDF approximations for specified points.";

QRMonConditionalCDFPlot::usage = "QRMonConditionalCDFPlot[ points_., opts] plots approximations of conditional CDF. \
If the points are not specified the pipeline value is used if it is an association of CDF's.";

QRMonOutliers::usage = "QRMonOutliers[] finds the outliers in the data.";

QRMonOutliersPlot::usage = "QRMonOutliersPlot[opts___] plots the outliers in the data. \
Finds them first if not already in the context.";

QRMonPickPathPoints::usage = "QRMonPickPathPoints[th_?NumberQ, opts___] picks points close to the regression functions \
using a specified threshold. \
With the option setting \"PickAboveThreshold\"->True the points picked are away from the regression functions.";

QRMonSeparate::usage = "QRMonSeparate[data_, opts___] separates the argument by the regression functions in the context. \
If no argument is given the data in the monad object is separated.";

QRMonSeparateToFractions::usage = "QRMonSeparateToFractions[data_, opts___] separates the argument by the regression functions \
in the context and find the corresponding fractions. \
If no argument is given the data in the monad object is separated.";

QRMonBandsSequence::usage = "Maps the time series values into a sequence of band indices derived from the regression quantiles.";

QRMonGridSequence::usage = "Maps the time series values into a sequence of indices derived from a values grid.";

QRMonMovingAverage::usage = "Moving average over a specified number of elements or a list of weights.";

QRMonMovingMedian::usage = "Moving median over a specified number of elements.";

QRMonMovingMap::usage = "Moving map with a specified function using a given window specification.";

QRMonSimulate::usage = "Simulates a time series using computed regression quantiles.";

QRMonLocalExtrema::usage = "Finds local extrema.";

QRMonFindLocalExtrema::usage = "Finds local extrema. (Same as QRMonLocalExtrema.)";

QRMonChowTestStatistic::usage = "Computes the Chow test statistic for identifying structural breaks in time series.";

PacletInstall["AntonAntonov/MonadMakers", AllowVersionUpdate -> False];
PacletInstall["AntonAntonov/QuantileRegression", AllowVersionUpdate -> False];
PacletInstall["AntonAntonov/OutlierIdentifiers", AllowVersionUpdate -> False];

Begin["`Private`"];

Needs["AntonAntonov`MonadicQuantileRegression`QRMon`"];

End[]; (* `Private` *)

EndPackage[]