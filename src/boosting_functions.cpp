#include "boosting_functions.h"

#define MAX(a,b) ((a) < (b) ? (b) : (a)) // define MAX function for use later

//[[Rcpp::export]]
void multiple_infection_strain_dependent(NumericVector &predicted_titres,
					 const NumericVector &theta,
					 const IntegerVector &cumu_infection_history,
					 const IntegerVector &masked_infection_history,
					 const IntegerVector &infection_map_indices, 
					 const IntegerVector &measurement_map_indices,
					 const NumericVector &antigenic_map_long, 
					 const NumericVector &antigenic_map_short, 
					 const NumericVector &waning,
					 const int &number_strains,
					 List additional_arguments){
  int n_samples = measurement_map_indices.size();
  int max_infections = cumu_infection_history.size();
  double mu;
  double mu_short = theta["mu_short"];
  double tau = theta["tau"];
  double n_inf, inf_map_index, wane;
  NumericVector mus = additional_arguments["mus"];
  IntegerVector boosting_vec_indices = additional_arguments["boosting_vec_indices"];
  for(int i = 0; i < max_infections; ++i){
    n_inf = cumu_infection_history[i] - 1.0;
    inf_map_index = infection_map_indices[i];
    mu = mus[boosting_vec_indices[inf_map_index]];
    wane = waning[i];
    if(masked_infection_history[i] > 0){
      for(int k = 0; k < n_samples; ++k){
	predicted_titres[k] += MAX(0, 1.0 - tau * n_inf)*
	  ((mu * antigenic_map_long[measurement_map_indices[k] * number_strains + inf_map_index]) + 
	   (mu_short * antigenic_map_short[measurement_map_indices[k] * number_strains + inf_map_index]) * 
	   wane);    
      }
    }
  }  
}

//[[Rcpp::export]]
void multiple_infection_base_boosting(NumericVector &predicted_titres,
				      const NumericVector &theta,
				      const IntegerVector &cumu_infection_history,
				      const IntegerVector &masked_infection_history,
				      const IntegerVector &infection_map_indices, 
				      const IntegerVector &measurement_map_indices,
				      const NumericVector &antigenic_map_long, 
				      const NumericVector &antigenic_map_short, 
				      const NumericVector &waning,
				      const NumericVector &seniority,
				      const int &number_strains,
				      const int &n_samples,
				      const int &max_infections
				      ){
  int index;
  double mu = theta["mu"];
  double mu_short = theta["mu_short"];
  double senior, inf_map_index, wane;

  for(int i = 0; i < max_infections; ++i){
    inf_map_index = infection_map_indices[i];
    wane = waning[i];
    senior = seniority[i];
    if(masked_infection_history[i] > 0){
      for(int k = 0; k < n_samples; ++k){
	index = measurement_map_indices[k] * number_strains + inf_map_index;
	predicted_titres[k] += senior *
	  ((mu * antigenic_map_long[index]) + 
	   (mu_short * antigenic_map_short[index]) * 
	   wane);    
      }
    }
  }
}

//[[Rcpp::export]]
void multiple_infection_titre_dependent_boost(NumericVector &predicted_titres, 
					      NumericVector &monitored_titres,
					      const NumericVector &theta,
					      const NumericVector &infection_times,
					      const IntegerVector &cumu_infection_history,
					      const IntegerVector &masked_infection_history,
					      const IntegerVector &infection_map_indices,
					      const IntegerVector &measurement_map_indices,
					      const NumericVector &antigenic_map_long, 
					      const NumericVector &antigenic_map_short, 
					      const NumericVector &waning,
					      const int &number_strains
					      ){
  double circulation_time;
  double monitored_titre = 0;
  double long_boost = 0;
  double short_boost = 0;
  double boost = 0;

  double mu = theta["mu"];
  double mu_short = theta["mu_short"];
  double tau = theta["tau"];
  double gradient = theta["gradient"];
  double boost_limit = theta["boost_limit"];
  double wane = theta["wane"];
  
  
  double n_inf, inf_map_index;

  int max_infections = infection_times.size();
  int n_samples = measurement_map_indices.size();

  for(int i = 0; i < max_infections; ++i){
    circulation_time = infection_times[i];
    n_inf = cumu_infection_history[i] - 1.0;
    inf_map_index = infection_map_indices[i];

    if(masked_infection_history[i] > 0){
      for(int ii = i - 1; ii >= 0; --ii){
	if(masked_infection_history[ii] > 0){
	  long_boost = MAX(0, 1.0 - tau*(cumu_infection_history[ii] - 1.0)) * // Antigenic seniority
	    (mu * antigenic_map_long[inf_map_index * 
				     number_strains + infection_map_indices[ii]]);      
      
	  // Short term cross reactive boost
	  short_boost =  MAX(0, 1.0 - tau*(cumu_infection_history[ii] - 1.0)) * // Antigenic seniority
	    (mu_short * antigenic_map_short[inf_map_index * 
					    number_strains + infection_map_indices[ii]]);

	  if(monitored_titres[ii] >= boost_limit){
	    long_boost =  long_boost * (1 - gradient * boost_limit); // Titre dependent boosting - at ceiling
	    short_boost =  short_boost * (1 - gradient * boost_limit); // Titre dependent boosting - at ceiling
	  } else {
	    long_boost = long_boost * (1 - gradient * monitored_titres[ii]); // Titre dependent boosting - below ceiling
	    short_boost = short_boost * (1 - gradient * monitored_titres[ii]); // Titre dependent boosting - below ceiling
	  }
	  long_boost = MAX(0, long_boost);
	  short_boost = MAX(0, short_boost);
	  boost = long_boost + short_boost * MAX(0, 1.0 - wane * (circulation_time - infection_times[ii]));
	  monitored_titre += boost;
	}
	monitored_titres[i] = monitored_titre;
      }
      for(int k = 0; k < n_samples; ++k){
	// How much boosting experienced from this infection?
	long_boost = MAX(0, 1.0 - tau * n_inf) *
	  (mu * antigenic_map_long[measurement_map_indices[k] * 
				   number_strains + inf_map_index]);
    
	// Short term cross reactive boost
	short_boost = MAX(0, 1.0 - tau * n_inf) *
	  (mu_short * antigenic_map_short[measurement_map_indices[k] * 
					  number_strains + inf_map_index]);
    
    
	if(monitored_titres[i] >= boost_limit){
	  long_boost =  long_boost * (1 - gradient * boost_limit); // Titre dependent boosting - at ceiling
	  short_boost =  short_boost * (1 - gradient * boost_limit); // Titre dependent boosting - at ceiling
	} else {
	  long_boost = long_boost * (1 - gradient * monitored_titres[i]); // Titre dependent boosting - below ceiling
	  short_boost = short_boost * (1 - gradient * monitored_titres[i]); // Titre dependent boosting - below ceiling
	}
	long_boost = MAX(0, long_boost);
	short_boost = MAX(0, short_boost);
	boost = long_boost + short_boost * waning[i];
	predicted_titres[k] += boost;
      }
    }
  }
}



void add_multiple_infections_boost(NumericVector &predicted_titres, 
				   NumericVector &monitored_titres,
				   const NumericVector &theta,
				   const NumericVector &infection_times,
				   const IntegerVector &cumu_infection_history,
				   const IntegerVector &masked_infection_history,
				   const IntegerVector &infection_map_indices,
				   const IntegerVector &measurement_map_indices,
				   const NumericVector &antigenic_map_long, 
				   const NumericVector &antigenic_map_short, 
				   const NumericVector &waning,
				   const NumericVector &seniority,
				   const int &number_strains,
				   const int &n_samples,
				   const int &max_infections,
				   const bool &titre_dependent_boosting,
				   const int &DOB,
				   const Nullable<List> &additional_arguments
				   ){ 
  if (titre_dependent_boosting) {
    multiple_infection_titre_dependent_boost(predicted_titres, 
					     monitored_titres,
					     theta,
					     infection_times,
					     cumu_infection_history,
					     masked_infection_history,
					     infection_map_indices,
					     measurement_map_indices,
					     antigenic_map_long, 
					     antigenic_map_short, 
					     waning,
					     number_strains);    
  } else if (additional_arguments.isNotNull()) {
    List _additional_arguments(additional_arguments);
    multiple_infection_strain_dependent(predicted_titres,
					theta, 
					cumu_infection_history,
					masked_infection_history,
					infection_map_indices,
					measurement_map_indices,
					antigenic_map_long,
					antigenic_map_short,
					waning,
					number_strains,
					_additional_arguments);	
  } else {
    multiple_infection_base_boosting(predicted_titres,
				     theta, 
				     cumu_infection_history,
				     masked_infection_history,
				     infection_map_indices,
				     measurement_map_indices,
				     antigenic_map_long,
				     antigenic_map_short,
				     waning,
				     seniority,
				     number_strains,
				     n_samples,
				     max_infections);							       
  }
}


void titre_data_fast_individual_base(NumericVector &predicted_titres,
				     const double &mu, 
				     const double &mu_short, 
				     const double &wane, 
				     const double &tau,
				     const NumericVector &infection_times,
				     const IntegerVector &infection_strain_indices_tmp,
				     const IntegerVector &measurement_strain_indices,
				     const NumericVector &sample_times,
				     const int &index_in_samples,
				     const int &end_index_in_samples,
				     const int &start_index_in_data1,
				     const IntegerVector &nrows_per_blood_sample,
				     const int &number_strains,
				     const NumericVector &antigenic_map_short,
				     const NumericVector &antigenic_map_long
				     ){
  double sampling_time;
  double time;
  double n_inf;
  double wane_amount;
  double seniority;
  
  int n_titres;
  int max_infections = infection_times.size();
  int end_index_in_data;
  int tmp_titre_index;
  int start_index_in_data = start_index_in_data1;
  int inf_map_index;
  int index;    

  // For each sample this individual has
  for(int j = index_in_samples; j <= end_index_in_samples; ++j){
    sampling_time = sample_times[j];
    n_inf = 1.0;	
    n_titres = nrows_per_blood_sample[j];
	
    end_index_in_data = start_index_in_data + n_titres;
    tmp_titre_index = start_index_in_data;

    // Sum all infections that would contribute towards observed titres at this time
    for(int x = 0; x < max_infections; ++x){
      if(sampling_time >= infection_times[x]){
	time = sampling_time - infection_times[x];
	wane_amount= MAX(0, 1.0 - (wane*time));
	seniority = MAX(0, 1.0 - tau*(n_inf - 1.0));
	inf_map_index = infection_strain_indices_tmp[x];

	for(int k = 0; k < n_titres; ++k){
	  index = measurement_strain_indices[tmp_titre_index + k]*number_strains + inf_map_index;
	  predicted_titres[tmp_titre_index + k] += seniority * 
	    ((mu*antigenic_map_long[index]) + (mu_short*antigenic_map_short[index])*wane_amount);
	}
	++n_inf;
      }	     
    }
    start_index_in_data = end_index_in_data;
  }
}
