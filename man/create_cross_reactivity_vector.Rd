% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/RcppExports.R
\name{create_cross_reactivity_vector}
\alias{create_cross_reactivity_vector}
\title{Convert melted antigenic map to cross reactivity}
\usage{
create_cross_reactivity_vector(x, sigma)
}
\arguments{
\item{x}{the melted antigenic map}

\item{sigma}{the cross reactivity waning parameter}
}
\value{
a vector of cross reactivity
}
\description{
Multiplies all elements of the provided vector, x such that y = 1 - sigma*x. Also makes sure that no calculated value is less than 0
}
