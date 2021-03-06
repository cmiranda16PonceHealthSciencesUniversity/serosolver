#' Simulate full data set
#'
#' Simulates a full data set for a given set of parameters etc.
#' @param par_tab the full parameter table controlling parameter ranges and values
#' @param group which group index to give this simulated data
#' @param n_indiv number of individuals to simulate
#' @param buckets time resolution of the simulated data. buckets=1 indicates annual time resolution; buckets=4 indicates quarterly; buckets=12 monthly
#' @param antigenic_map (optional) A data frame of antigenic x and y coordinates. Must have column names: x_coord; y_coord; inf_times. See \code{\link{example_antigenic_map}}
#' @param strain_isolation_times (optional) If no antigenic map is specified, this argument gives the vector of times at which individuals can be infected
#' @param measured_strains vector of strains that have titres measured matching entries in strain_isolation_times
#' @param sampling_times possible sampling times for the individuals, matching entries in strain_isolation_times
#' @param nsamps the number of samples each individual has (eg. nsamps=2 gives each individual 2 random sampling times from sampling_times)
#' @param titre_sensoring numeric between 0 and 1, used to censor a proportion of titre observations at random (MAR)
#' @param age_min simulated age minimum
#' @param age_max simulated age maximum
#' @param attack_rates a vector of attack_rates for each entry in strain_isolation_times to be used in the simulation (between 0 and 1)
#' @param repeats number of repeat observations for each year
#' @param mu_indices default NULL, optional vector giving the index of `mus` that each strain uses the boosting parameter from. eg. if there are 6 circulation years in strain_isolation_times and 3 strain clusters, then this might be c(1,1,2,2,3,3)
#' @param measurement_indices default NULL, optional vector giving the index of `measurement_bias` that each strain uses the measurement shift from from. eg. if there's 6 circulation years and 3 strain clusters, then this might be c(1,1,2,2,3,3)
#' @param add_noise if TRUE, adds observation noise to the simulated titres
#' @return a list with: 1) the data frame of titre data as returned by \code{\link{simulate_group}}; 2) a matrix of infection histories as returned by \code{\link{simulate_infection_histories}}; 3) a vector of ages
#' @family simulation_functions
#' @examples
#' data(example_par_tab)
#' data(example_antigenic_map)
#'
#' ## Times at which individuals can be infected
#' strain_isolation_times <- example_antigenic_map$inf_times
#' ## Simulate some random attack rates between 0 and 0.2
#' attack_rates <- runif(length(strain_isolation_times), 0, 0.2)
#' ## Vector giving the circulation times of measured strains
#' sampled_viruses <- seq(min(strain_isolation_times), max(strain_isolation_times), by=2)
#' all_simulated_data <- simulate_data(par_tab=example_par_tab, group=1, n_indiv=50,    
#'                                    strain_isolation_times=strain_isolation_times,
#'                                    measured_strains=sampled_viruses,
#'                                    sampling_times=2010:2015, nsamps=2, antigenic_map=example_antigenic_map, 
#'                                    age_min=10,age_max=75,
#'                                    attack_rates=attack_rates, repeats=2)
#' titre_dat <- all_simulated_data$data
#' titre_dat <- merge(titre_dat, all_simulated_data$ages)
#' @export
simulate_data <- function(par_tab,
                          group = 1,
                          n_indiv = 100,
                          buckets = 1,
                          antigenic_map = NULL,
                          strain_isolation_times = NULL,
                          measured_strains = NULL,
                          sampling_times,
                          nsamps = 2,
                          titre_sensoring = 0,
                          age_min = 5, age_max = 80,
                          attack_rates,
                          repeats = 1,
                          mu_indices = NULL,
                          measurement_indices = NULL,
                          add_noise = TRUE) {

    if (!is.null(antigenic_map)) {
      strain_isolation_times <- unique(antigenic_map$inf_times) # How many strains are we testing against and what time did they circulate
    } else {
      antigenic_map <- data.frame("x_coord"=1,"y_coord"=1,"inf_times"=strain_isolation_times)
    }
    
    ## Check attack_rates entry
    check_attack_rates(attack_rates, strain_isolation_times)
    ## Check the inputs of par_tab
    check_par_tab(par_tab)
    message("Simulating data\n")    

    ## Extract parameter type indices from par_tab, to split up
    ## similar parameters in model solving functions
    option_indices <- which(par_tab$type == 0)
    theta_indices <- which(par_tab$type %in% c(0, 1))
    measurement_indices_par_tab <- which(par_tab$type == 3)
    mu_indices_par_tab <- which(par_tab$type == 6)
    
    ## Extract parameters
    par_names_theta <- par_tab[theta_indices, "names"]
    pars <- par_tab$values
    theta <- pars[theta_indices]
    names(theta) <- par_names_theta

    mus <- NULL
    if (!is.null(mu_indices)) {
        message(cat("Strain specific boosting\n"))
        mus <- pars[mu_indices_par_tab]
    }
    
    measurement_bias <- NULL
    if (!is.null(measurement_indices)) {
        message(cat("Measurement bias\n"))
        measurement_bias <- pars[measurement_indices_par_tab]
    }
    
    if (is.null(measured_strains)) {
        measured_strains <- strain_isolation_times
    }
    
    ## Simulate ages, where "age" is the age at the time of the last sample
    DOBs <- max(sampling_times) - floor(runif(n_indiv, age_min, age_max))
    
    ## Simulate infection histories
    tmp <- simulate_infection_histories(
        attack_rates, strain_isolation_times,
        sampling_times, DOBs
    )
    infection_history <- tmp[[1]]
    ARs <- tmp[[2]]
    ## Simulate titre data
    sim_dat <- simulate_group(
        n_indiv, theta, infection_history,
        strain_isolation_times, measured_strains,
        sampling_times,
        nsamps, antigenic_map, repeats,
        mus, mu_indices, measurement_bias,
        measurement_indices, add_noise
    )
    y <- sim_dat$titre_dat
    infection_history <- sim_dat$infection_history

    ## Need to update attack rate estimate based on strain mask, which is corrected in simulate_group
    age_mask <- create_age_mask(DOBs, strain_isolation_times)
    strain_mask <- create_strain_mask(y, strain_isolation_times)
    ## Can't be exposed or infected after the last sampling time
    for (i in 1:nrow(infection_history)) {
        if (strain_mask[i] < ncol(infection_history)) {
            infection_history[i, (strain_mask[i] + 1):ncol(infection_history)] <- 0
        }
    }

    n_alive <- sapply(seq(1, length(strain_isolation_times)), function(x)
        sum(age_mask <= x))
    ARs <- colSums(infection_history) / n_alive

    ## Randomly censor titre values
    y$titre <- y$titre * sample(c(NA, 1), nrow(y), prob = c(titre_sensoring, 1 - titre_sensoring), replace = TRUE)
    y$group <- group

    ages <- data.frame("individual" = 1:n_indiv, "DOB" = DOBs)
    attack_rates <- data.frame("year" = strain_isolation_times, "AR" = ARs)
    return(list(
        data = y, infection_histories = infection_history,
        ages = ages, attack_rates = attack_rates, phis = attack_rates
    ))
}



#' Simulate group data
#'
#' Simulates a full set of titre data for n_indiv individuals with known theta and infection_histories. Each individual gets nsamps random samples from sampleTimes, and infections can occur at any of strain_isolation_times
#' @inheritParams simulate_data
#' @param theta the named parameter vector
#' @param infection_histories the matrix of 1s and 0s giving presence/absence of infections for each individual
#' @param mus default NULL, optional vector of boosting parameters for each strain
#' @return a data frame with columns individual, samples, virus and titre of simulated data
#' @family simulation_functions
#' @export
#' @seealso \code{\link{simulate_individual}}, \code{\link{simulate_individual_faster}}
simulate_group <- function(n_indiv,
                           theta,
                           infection_histories,
                           strain_isolation_times,
                           measured_strains,
                           sample_times,
                           nsamps,
                           antigenic_map,
                           repeats = 1,
                           mus = NULL,
                           mu_indices = NULL,
                           measurement_bias = NULL,
                           measurement_indices = NULL,
                           add_noise = TRUE) {

  ## Create antigenic map for short and long term boosting
  antigenic_map_melted <- melt_antigenic_coords(antigenic_map[, c("x_coord", "y_coord")])
  antigenic_map_long <- create_cross_reactivity_vector(antigenic_map_melted, theta["sigma1"])
  antigenic_map_short <- create_cross_reactivity_vector(antigenic_map_melted, theta["sigma2"])
  antigenic_distances <- c(antigenic_map_melted)
  dat <- NULL
  ## For each individual
  for (i in 1:n_indiv) {
    ## Choose random sampling times
    ## If there is one sampling time, then repeat the same sampling time
    if (length(sample_times) == 1) {
      samps <- rep(sample_times, nsamps)
    } else {
      samps <- sample(sample_times, nsamps)
      samps <- samps[order(samps)]
    }

    ## Individuals can't be infected after their latest sampling time
    strain_mask <- max(which(max(samps) >= strain_isolation_times))
    if (strain_mask < ncol(infection_histories)) {
      infection_histories[i, (strain_mask + 1):ncol(infection_histories)] <- 0
    }
    y <- as.data.frame(simulate_individual_faster(
      theta,
      infection_histories[i, ],
      antigenic_map_long,
      antigenic_map_short,
      antigenic_distances,
      samps,
      strain_isolation_times,
      measured_strains,
      mus, mu_indices,
      measurement_bias,
      measurement_indices,
      add_noise, repeats
    ))
    ## Record individual ID
    y$indiv <- i
    colnames(y) <- c("samples", "virus", "titre", "run", "individual")
    ## Combine data
    dat <- rbind(dat, y[, c("individual", "samples", "virus", "titre", "run")])
  }
  return(list(titre_dat = dat, infection_history = infection_histories))
}
#' Simulate individual data quickly
#'
#' FOR USERS: USE \code{\link{simulate_individual}}. This function does the same thing, but with a few short cuts for speed. Simulates a full set of titre data for an individual with known theta and infection_history.
#' @inheritParams simulate_group
#' @param infection_history the vector of 1s and 0s giving presence/absence of infections
#' @param antigenic_map_long the long term antigenic cross reactivity map generated from \code{\link{create_cross_reactivity_vector}}
#' @param antigenic_map_short the short term antigenic cross reactivity map generated from \code{\link{create_cross_reactivity_vector}}
#' @param antigenic_distances same dimensions as antigenic_map_long and antigenic_map_short, but gives the raw euclidean antigenic distances
#' @param sampling_times vector of times at which blood samples were taken
#' @param measured_strains vector of which strains had titres measured in `strain_isolation_times`
#' @return a data frame with columns samples, virus and titre of simulated data
#' @family simulation_functions
#' @export
simulate_individual_faster <- function(theta,
                                       infection_history,
                                       antigenic_map_long,
                                       antigenic_map_short,
                                       antigenic_distances,
                                       sampling_times,
                                       strain_isolation_times,
                                       measured_strains,
                                       mus = NULL, mu_indices = NULL,
                                       measurement_bias = NULL, measurement_indices = NULL,
                                       add_noise = TRUE, repeats = 1,
                                       DOB = NULL) {
  if (is.null(mus)) {
    mus <- c(-1)
    mu_indices <- c(-1)
  }

  inf_hist <- matrix(nrow = 1, ncol = length(infection_history))
  inf_hist[1, ] <- infection_history

  n_samps <- length(sampling_times)

  ## length(measured_strains) observatios made per blood sample
  rows_per_blood <- rep(length(measured_strains), n_samps)

  ## Cumulative of the above for the algorithm
  cumu_rows <- c(0, sum(rows_per_blood))

  ## Iterate through sample times sample_times[0:(n_samps-1)] to solve the model
  rows_per_indiv <- c(0, n_samps)

  ## Entries in the antigenic map
  strain_indices <- match(strain_isolation_times, strain_isolation_times) - 1

  ## Entries in the antigenic map for each measured strain
  measured_strain_indices <- match(rep(measured_strains, n_samps), strain_isolation_times) - 1
  dat <- matrix(nrow = length(measured_strain_indices) * repeats, ncol = 4) ## To store simulated data

  ## Go into C++ code to solve titre model
  titres <- titre_data_fast(
    theta, inf_hist, strain_isolation_times, strain_indices,
    sampling_times, rows_per_indiv, cumu_rows,
    rows_per_blood, measured_strain_indices,
    antigenic_map_long,
    antigenic_map_short,
    antigenic_distances,
    mus, mu_indices, FALSE
  )

  ## Repeated each simulated titre per observation repeat
  titres <- rep(titres, repeats)
  ## Housekeeping for return data
  sampling_times <- rep(sampling_times, rows_per_blood)
  enum_repeats <- rep(1:repeats, each = length(sampling_times))
  sampling_times <- rep(sampling_times, repeats)
  dat[, 1] <- sampling_times
  dat[, 2] <- rep(rep(measured_strains, n_samps), repeats)

  ## Add observation noise, including measurement bias if selected
  if (add_noise) {
    if (!is.null(measurement_indices)) {
      dat[, 3] <- add_noise(titres, theta, measurement_bias, measurement_indices[match(dat[, 2], strain_isolation_times)])
    } else {
      dat[, 3] <- add_noise(titres, theta, NULL, NULL)
    }
  } else {
    dat[, 3] <- titres
  }
  dat[, 4] <- enum_repeats
  return(dat)
}


#' Simulate individual data
#'
#' Simulates a full set of titre data for an individual with known theta and infection_history.
#' @inheritParams simulate_group
#' @param infection_history the vector of 1s and 0s giving presence/absence of infections
#' @param sampling_times vector of times at which blood samples were taken
#' @param measured_strains vector of which strains had titres measured in `strain_isolation_times`
#' @return a data frame with columns samples, virus and titre of simulated data
#' @family simulation_functions
#' @export
#' @examples
#' data(example_par_tab)
#' data(example_antigenic_map)
#' infection_history <- sample(c(0,1),size=nrow(example_antigenic_map), replace=TRUE,prob=c(0.9,0.1))
#' pars <- example_par_tab$values
#' names(pars) <- example_par_tab$names
#' strain_isolation_times <- example_antigenic_map$inf_times
#' y <- simulate_individual(pars, infection_history, example_antigenic_map, 2009, 
#'                          strain_isolation_times,strain_isolation_times,add_noise=FALSE)
simulate_individual <- function(theta,
                                infection_history,
                                antigenic_map,
                                sampling_times,
                                strain_isolation_times,
                                measured_strains,
                                mus = NULL, mu_indices = NULL,
                                measurement_bias = NULL, measurement_indices = NULL,
                                add_noise = TRUE, repeats = 1,
                                DOB = NULL) {
  if (is.null(mus)) {
    mus <- c(-1)
    mu_indices <- c(-1)
  }

  ## Create antigenic map for short and long term boosting
  antigenic_map_melted <- melt_antigenic_coords(antigenic_map[, c("x_coord", "y_coord")])
  antigenic_map_long <- create_cross_reactivity_vector(antigenic_map_melted, theta["sigma1"])
  antigenic_map_short <- create_cross_reactivity_vector(antigenic_map_melted, theta["sigma2"])
  antigenic_distances <- c(antigenic_map_melted)
  inf_hist <- matrix(nrow = 1, ncol = length(infection_history))
  inf_hist[1, ] <- infection_history

  n_samps <- length(sampling_times)
  ## length(measured_strains) observatios made per blood sample
  rows_per_blood <- rep(length(measured_strains), n_samps)

  ## Cumulative of the above for the algorithm
  cumu_rows <- c(0, sum(rows_per_blood))

  ## Iterate through sample times sample_times[0:(n_samps-1)] to solve the model
  rows_per_indiv <- c(0, n_samps)

  ## Entries in the antigenic map
  strain_indices <- match(strain_isolation_times, strain_isolation_times) - 1

  ## Entries in the antigenic map for each measured strain
  measured_strain_indices <- match(rep(measured_strains, n_samps), strain_isolation_times) - 1
  dat <- matrix(nrow = length(measured_strain_indices) * repeats, ncol = 4) ## To store simulated data

  ## Go into C++ code to solve titre model
  titres <- titre_data_fast(
    theta, inf_hist, strain_isolation_times, strain_indices,
    sampling_times, rows_per_indiv, cumu_rows,
    rows_per_blood, measured_strain_indices,
    antigenic_map_long, antigenic_map_short,
    antigenic_distances,
    mus, mu_indices
  )

  ## Repeated each simulated titre per observation repeat
  titres <- rep(titres, repeats)
  ## Housekeeping for return data
  sampling_times <- rep(sampling_times, rows_per_blood)
  enum_repeats <- rep(1:repeats, each = length(sampling_times))
  sampling_times <- rep(sampling_times, repeats)
  dat[, 1] <- sampling_times
  dat[, 2] <- rep(rep(measured_strains, n_samps), repeats)
  ## Add observation noise, including measurement bias if selected
  if (add_noise) {
    if (!is.null(measurement_indices)) {
      dat[, 3] <- add_noise(titres, theta, measurement_bias, measurement_indices[match(dat[, 2], strains)])
    } else {
      dat[, 3] <- add_noise(titres, theta, NULL, NULL)
    }
  } else {
    dat[, 3] <- titres
  }
  dat[, 4] <- enum_repeats
  return(dat)
}

#' Add noise
#'
#' Adds truncated noise to titre data
#' @param y the titre
#' @param theta a vector with MAX_TITRE and error parameters
#' @return a noisy titre
#' @export
#' @examples
#' \dontrun{
#' ## ... example in simulate_individual
#' pars <- c("error"=1)
#' y <- runif(100)
#' noisy_y <- add_noise(y, pars)
#' }
add_noise <- function(y, theta, measurement_bias = NULL, indices = NULL) {
  ## Draw from normal
  if (!is.null(measurement_bias)) {
    noise_y <- floor(rnorm(length(y), mean = y + measurement_bias[indices], sd = theta["error"]))
  } else {
    noise_y <- floor(rnorm(length(y), mean = y, sd = theta["error"]))
  }

  ## If outside of bounds, truncate
  noise_y[noise_y < 0] <- 0
  noise_y[noise_y > theta["MAX_TITRE"]] <- theta["MAX_TITRE"]
  return(noise_y)
}

#' Simulate attack rates
#'
#' Given a number of possible infection years, simulates attack rates from a log normal distribution with specified mean and standard deviation.
#' @param infection_years the number of infection years
#' @param mean_par the mean of the log normal
#' @param sd_par the sd of the log normal
#' @param large_first_year simulate an extra large attach rate in the first year?
#' @param big_year_mean if large first year, what mean to use?
#' @return a vector of attack rates
#' @family simulation_functions
#' @export
simulate_attack_rates <- function(infection_years, mean_par = 0.15, sd_par = 0.5,
                                  large_first_year = FALSE, big_year_mean = 0.5) {
  attack_year <- rlnorm(infection_years, meanlog = log(mean_par) - sd_par^2 / 2, sdlog = sd_par)
  if (large_first_year) attack_year[1] <- rlnorm(1, meanlog = log(big_year_mean) - (sd_par / 2)^2 / 2, sdlog = sd_par / 2)
  return(attack_year)
}

#' Simulate infection histories
#'
#' Given a vector of infection probabilities and potential infection times, simulates infections for each element of ages (ie. each element is an individual age. Only adds infections for alive individuals)
#' @param p_inf a vector of attack rates (infection probabilities) for each year
#' @param strain_isolation_times the vector of possible infection times
#' @param sampling_times vector of potential sampling times
#' @param DOBs a vector of ages for each individual
#' @return a list with a matrix of infection histories for each individual in ages and the true attack rate for each epoch
#' @family simulation_functions
#' @examples
#' p_inf <- runif(40,0.1,0.4)
#' strain_isolation_times <- seq_len(40) + 1967
#' n_indivs <- 100
#' sampling_times <- rep(max(strain_isolation_times), n_indivs)
#' DOBs <- rep(min(strain_isolation_times), n_indivs)
#' inf_hist <- simulate_infection_histories(p_inf, strain_isolation_times, sampling_times, DOBs)
#' @export
simulate_infection_histories <- function(p_inf, strain_isolation_times, sampling_times, DOBs) {
  n_strains <- length(p_inf) # How many strains
  n_indiv <- length(DOBs) # How many individuals
  indivs <- 1:n_indiv
  ## Empty matrix
  infection_histories <- matrix(0, ncol = n_strains, nrow = n_indiv)

  ## Simulate attack rates
  attack_rates <- p_inf

  ## Should this be necessary?
  attack_rates[attack_rates > 1] <- 1
  ARs <- numeric(n_strains)

  age_mask <- create_age_mask(DOBs, strain_isolation_times)

  ## For each strain (ie. each infection year)
  for (i in 1:n_strains) {
    ## If there are strains circulating beyond the max sampling times, then alive==0
    if (max(sampling_times) >= strain_isolation_times[i]) {
      ## Find who was alive (all we need sampling_times for is its max value)
      alive <- which(age_mask <= i)

      ## Sample a number of infections for the alive individuals, and set these entries to 1
      y <- round(length(indivs[alive]) * attack_rates[i])
      # y <- rbinom(1, length(indivs[alive]),attack_rates[i])
      ARs[i] <- y / length(indivs[alive])
      x <- sample(indivs[alive], y)
      infection_histories[x, i] <- 1
    } else {
      ARs[i] <- 0
    }
  }
  return(list(infection_histories, ARs))
}


#' Generates attack rates from an SIR model with fixed beta/gamma, specified final attack rate and the number of time "buckets" to solve over ie. buckets=12 returns attack rates for 12 time periods
generate_ar_annual <- function(AR, buckets) {
  SIR_odes <- function(t, x, params) {
    S <- x[1]
    I <- x[2]
    R <- x[3]
    inc <- x[4]

    beta <- params[1]
    gamma <- params[2]
    dS <- -beta * S * I
    dI <- beta * S * I - gamma * I
    dR <- gamma * I
    dinc <- beta * S * I
    list(c(dS, dI, dR, dinc))
  }
  R0 <- 1.2
  gamma <- 1 / 5
  beta <- R0 * gamma
  t <- seq(0, 360, by = 0.1)
  results <- as.data.frame(deSolve::ode(
    y = c(S = 1, I = 0.0001, R = 0, inc = 0),
    times = t, func = SIR_odes,
    parms = c(beta, gamma)
  ))
  incidence <- diff(results$inc)
  incidence <- incidence * AR / sum(incidence)
  group <- 360 * 10 / buckets
  monthly_risk <- colSums(matrix(incidence, nrow = group))
  return(monthly_risk)
}


simulate_ars_buckets <- function(infection_years, buckets, mean_par = 0.15, sd_par = 0.5,
                                 large_first_year = FALSE, big_year_mean = 0.5) {
  n <- ceiling(length(infection_years) / buckets)
  attack_year <- rlnorm(n, meanlog = log(mean_par) - sd_par^2 / 2, sdlog = sd_par)
  if (large_first_year) attack_year[1] <- rlnorm(1, meanlog = log(big_year_mean) - (sd_par / 2)^2 / 2, sdlog = sd_par / 2)
  ars <- NULL

  for (i in seq_along(attack_year)) {
    ars <- c(ars, generate_ar_annual(attack_year[i], buckets))
  }

  ars <- ars[1:length(infection_years)]
  return(ars)
}

simulate_ars_spline <- function(infection_years, buckets, mean_par = 0.15, sd_par = 0.5, large_first_year = FALSE, big_year_mean = 0.5, knots, theta) {
  infection_years <- infection_years[seq(1, length(infection_years), by = buckets)] / buckets
  n <- length(infection_years)
  attack_year <- rlnorm(n, meanlog = log(mean_par) - sd_par^2 / 2, sdlog = sd_par)
  if (large_first_year) attack_year[1] <- rlnorm(1, meanlog = log(big_year_mean) - (sd_par / 2)^2 / 2, sdlog = sd_par / 2)
  ars <- generate_phis(attack_year, knots, theta, n, buckets)
  return(ars)
}
