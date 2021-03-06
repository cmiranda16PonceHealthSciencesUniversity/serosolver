% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/mcmc_help.R
\name{setup_infection_histories_old}
\alias{setup_infection_histories_old}
\title{Propose initial infection histories - OLD VERSION}
\usage{
setup_infection_histories_old(
  titre_dat,
  strain_isolation_times,
  sample_prob,
  titre_cutoff = 3
)
}
\arguments{
\item{titre_dat}{the matrix of titres data with columns for individual, sample, and titre}

\item{strain_isolation_times}{vector of real times for all strains}

\item{sample_prob}{given an infection seems likely based on titre, suggest infection with 1 minus this probability}

\item{titre_cutoff}{specifies how high the titre must be to imply an infection}
}
\value{
an nxm matrix of infection histories containing 1s and 0s, where n is the number of individuals and m is the number of potential infecting strains
}
\description{
Given a matrix of titre data, proposes plausible initial infection histories from which to begin MCMC sampling.
NOTE - MIGHT NEED TO UPDATE THIS FOR GROUPS
}
\examples{
data(example_titre_dat)
data(example_antigenic_map)
start_inf <- setup_infection_histories_old(example_titre_dat, example_antigenic_map$inf_times, 0.2, 3)
}
\seealso{
Other setup_infection_histories: 
\code{\link{setup_infection_histories_titre}()},
\code{\link{setup_infection_histories_total}()},
\code{\link{setup_infection_histories}()}
}
\concept{setup_infection_histories}
