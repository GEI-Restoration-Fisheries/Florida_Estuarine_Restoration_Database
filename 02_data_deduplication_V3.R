# ==============================================================================
# ==============================================================================
# ==============================================================================
# DUPLICATION CLEANING 
# ==============================================================================
# ==============================================================================
# ==============================================================================

# This methodology will begin with identifying the potential
# duplicates within datasets, and then addressing the duplicates between datasets.
# Will address between datasets by starting with the database that has the most
# duplication over other databases. 

# This will be three-tier methodology using two different duplication keys and 
# precision of inputs. 

library(dplyr)
library(tidyr)

#clean environment
rm(list = ls())

# Load Rdata
load(paste(getwd(),"/Florida Estuarine Restoration Database/master_db.Rdata", sep = ""))


# Load duplication function that outputs the potential duplicates within and 
# between datasets, and counts of duplicates as a matrix:
duplicate_analysis <- function(data, dup_key, dataset_col = "Data_Source", Proj_Group_ID = TRUE, Duplicate = TRUE) {
  
  # INFORMATION ON FUNCTION ARGUMENTS: -----------------------------------------
  # INPUTS
  # data                     data frame 
  # dup_key                  unquoted column name(s) to use as duplication key (e.g. c(Latitude, Project_Name))
  # dataset_col              name of column that identifies the dataset (default: "Data_Source")
  # Proj_Group_ID            logical; whether to consider Project_Group_ID when identifying duplicates (default: TRUE where all records are included)
  # Duplicate                logical; whether to consider records already flagged as duplicates (default: TRUE where all records are included)
  
  
  dataset_sym <- rlang::sym(dataset_col)
  
  # --------------------------------------------------
  # Create duplicate key
  # --------------------------------------------------
  data_key <- data %>%
    mutate(dup_key = {{ dup_key }})
  
  
  # Do consider Duplicate flag when identifying duplicates (i.e., exclude records already flagged as duplicates)
  if (Duplicate == TRUE) { data_key <- data_key %>% filter(Duplicate != 1)} else { data_key <- data_key }
  
  
  # --------------------------------------------------
  # Remove duplicate keys ONLY when:
  #   - They occur within the SAME dataset
  #   - AND they share the same Project_Group_ID
  #   - AND the dup_key does NOT occur in another dataset
  #   - AND Project_Group_ID is NOT NA (optional consideration)
  # --------------------------------------------------
  
  # --------------------------------------------------
  # Within-dataset duplicates
  # Exclude groups where Project_Group_ID is identical
  # (but keep NA values)
  # --------------------------------------------------
  
  if (Proj_Group_ID == TRUE) {
  
    # DO consider Project_Group_ID when identifying duplicates (i.e., remove 
    # duplicates within datasets where there is a value for Project_Group_ID 
    #and the value is the same across records within the dataset)
    
  within_dataset_dups <- data_key %>%
    group_by(!!dataset_sym, dup_key) %>%
    filter(n() > 1) %>%
    # remove groups where Project_Group_ID is the same (excluding NA)
    filter(
      !( !is.na(Project_Group_ID) &
           n_distinct(Project_Group_ID[!is.na(Project_Group_ID)]) == 1 )
    ) %>%
    ungroup() %>%
    arrange(!!dataset_sym, dup_key)
  
  } else {
    
    # DO NOT consider Project_Group_ID when identifying dataset duplicates 
    # (i.e., keep all duplicates within datasets regardless of whether there is
    # a value for Project_Group_ID)
    
    within_dataset_dups <- data_key %>%
      group_by(!!dataset_sym, dup_key) %>%
      filter(n() > 1) %>%
      ungroup() %>%
      arrange(!!dataset_sym, dup_key)
    
  } 
  
  # ---
  
  within_dataset_dups_records <- data_key %>%
    semi_join(within_dataset_dups, by = c(dataset_col, "dup_key"))
  
  within_counts <- within_dataset_dups %>%
    distinct(!!dataset_sym, dup_key) %>%
    count(!!dataset_sym, name = "within_dups")
  
  # --------------------------------------------------
  # Between-dataset duplicates
  # --------------------------------------------------
  between_dataset_dups <- data_key %>%
    distinct(dup_key, !!dataset_sym) %>%
    group_by(dup_key) %>%
    filter(n() > 1) %>%
    ungroup()
  
  between_dataset_dups_records <- data_key %>%
    semi_join(between_dataset_dups, by = "dup_key")
  
  # --------------------------------------------------
  # Duplication matrix
  # --------------------------------------------------
  all_data_sources <- sort(unique(data_key[[dataset_col]]))
  
  dup_matrix <- between_dataset_dups %>%
    mutate(present = 1) %>%
    pivot_wider(names_from = !!dataset_sym,
                values_from = present,
                values_fill = list(present = 0))
  
  # Add missing datasets
  missing_cols <- setdiff(all_data_sources, colnames(dup_matrix))
  if (length(missing_cols) > 0) {
    dup_matrix[missing_cols] <- 0
  }
  
  dup_matrix <- dup_matrix %>%
    select(dup_key, all_of(all_data_sources))
  
  dataset_matrix <- dup_matrix %>%
    select(-dup_key) %>%
    as.matrix()
  
  overlap_matrix <- t(dataset_matrix) %*% dataset_matrix
  
  # Fill diagonal with within-dataset counts
  diag(overlap_matrix) <- within_counts$within_dups[
    match(rownames(overlap_matrix), within_counts[[dataset_col]])
  ]
  
  overlap_matrix[is.na(overlap_matrix)] <- 0
  
  overlap_matrix_df <- as.data.frame(overlap_matrix)
  
  print(overlap_matrix_df)
  
  # --------------------------------------------------
  # Total duplicates
  # --------------------------------------------------
  
  total_rows_flagged <- (nrow(within_dataset_dups_records) + nrow(between_dataset_dups_records))
  total_dups <- sum(overlap_matrix[lower.tri(overlap_matrix)]) + sum(diag(overlap_matrix))
  print(paste0("Total rows identified as potential duplicates: ", total_rows_flagged))
  print(paste0("Total potential duplicates identified within and between databases: ", total_dups))
  print(paste0("Total potential duplicates identified within databases: ", sum(diag(overlap_matrix))))
  print(paste0("Total potential duplicates identified between databases: ", sum(overlap_matrix[lower.tri(overlap_matrix)])))
  
  # --------------------------------------------------
  # Output
  # --------------------------------------------------
  return(list(
    overlap_matrix = overlap_matrix_df,
    within_records = within_dataset_dups_records,
    between_records = between_dataset_dups_records,
    total_duplicates = total_dups,
    total_dup_records = total_rows_flagged
  ))
  
  print(overlap_matrix_df)
}


# Create cleaned master database to iteratively update as duplicates are identified and resolved:
master_db_dedup <- master_db %>%
  # Set up columns for merging and flagging duplicates to drop
  mutate(Merged_Record_ID = as.character(NA),
         Duplicate = 0,
         Data_Source_2 = as.character(NA),
         tier1_dup_key = paste(Latitude, Longitude, Project_Name, Project_Description),
         tier2_dup_key = paste(Project_Name))

# ==============================================================================
# ------------------------------------------------------------------------------
# TIER 1: DUPLICATION KEY: Project_Name,Project_Description,Latitude,Longitude 
# ------------------------------------------------------------------------------
# ==============================================================================

# ------------------------------------------------------------------------------
# IDENTIFY POTENTIAL DUPLICATE PROJECTS WITHIN AND BETWEEN DATASETS ---
# ------------------------------------------------------------------------------

{
# Create a duplication matrix key that combines Latitude, Longitude, 
# Project Name, and Project Description to identify potential duplicates across 
# data sets. 

tier1 <- duplicate_analysis(
  data = master_db_dedup,
  dup_key = paste(Latitude, Longitude, Project_Name, Project_Description),
  Proj_Group_ID = FALSE)

# Create the reference 
tier1_key <- master_db_dedup %>%
  mutate(tier1_dup_key = paste(Latitude, Longitude, Project_Name, Project_Description))
}

# -----------------------------------------------------------------------------
# HANDLE WITHIN-DATASET DUPLICATES 
# ------------------------------------------------------------------------------

{
  
  # Add Decision_ID assigned to each unique dup_key for potential within-dataset duplicates: 
  tier1_within_records <- tier1$within_records %>%
    group_by(dup_key) %>% 
    arrange(Data_Source, .by_group = TRUE) %>%
    mutate(Decision_ID = cur_group_id()) %>%
    ungroup()
  
  # Export the potential within-dataset duplicates for manual review: 
  write.csv(tier1_within_records, file = paste(getwd(), 
            "/Deduplication","/tier1_within_dataset_duplicates_preprocessed.csv", sep = ""), row.names = FALSE) 
  
  
  # Create table to input decisions upon review: 
  tier1_within_review <- tier1$within_records %>%
    
      # Keep only fields needed for review table
      select(dup_key,Data_Source,Original_Project_ID) %>%
      
      # Order records within the dup_key
      group_by(dup_key) %>% arrange(Data_Source, .by_group = TRUE) %>%
      mutate(n_records = row_number()) %>% ungroup() %>%
      
      # Create numbered columns
      pivot_wider(
      names_from = n_records,
      values_from = c(Data_Source, Original_Project_ID),
      names_glue = "{.value}_{n_records}") %>%
      
      # Add column that is number of rows within 
      mutate(n_records = rowSums(!is.na(select(., starts_with("Data_Source_"))))) %>%
      
      # Add review fields
      mutate(Decision_ID = row_number(), Action = "", Review_Notes = "") %>%
      
      # Reorder columns
      select(Decision_ID, dup_key, n_records, Action,everything())
  
  # Export template of decision-making table for within-dataset duplicates: 
  write.csv(tier1_within_review, file = paste(getwd(), 
           "/Deduplication","/tier1_within_dataset_review.csv", sep = ""), row.names = FALSE) 
  
  
  # Create a template for duplicate actions and export: 
  within_dup_actions <- data.frame(
    Decision_ID = integer(),
    Data_Source = character(),
    Original_Project_ID = character(),
    Project_Name = character(),
    Action = character(),
    Merge_Template = character(),
    tier1_dup_key = character())
  
  write.csv(within_dup_actions, file = paste(getwd(), 
           "/Deduplication","/tier1_within_dataset_actions_template.csv", sep = ""), row.names = FALSE)
  
  
  # Import decision-making table following review:
  within_dup_actions <- read.csv(
    file.path(getwd(),
              "Deduplication",
              "tier1_within_dataset_actions.csv"),
    stringsAsFactors = FALSE)
  
  
  # Update master_db_dedup based on manual review of within-dataset duplicates 
  master_db_dedup <- master_db_dedup %>%
    left_join(
      tier1_within_records %>%
        select(dup_key, Decision_ID, Original_Project_ID, Data_Source) %>%
        distinct() %>%
        rename(tier1_dup_key = dup_key,
          t1w_Decision_ID = Decision_ID),
      by = c("tier1_dup_key","Original_Project_ID","Data_Source")) 
  
  
  # Clean white space master_db_dedup and within_dup_actions: 
  clean_text <- function(x) {
    x %>%
      str_replace_all("\r\n", "\n") %>%
      str_replace_all("\r", "\n") %>%
      str_squish()}
  
  master_db_dedup <- master_db_dedup %>%
    mutate(tier1_dup_key = clean_text(tier1_dup_key))
  
  within_dup_actions <- within_dup_actions %>%
    mutate(tier1_dup_key = clean_text(tier1_dup_key))

  
# Loop through decisions: 
for(decision in unique(within_dup_actions$Decision_ID)) {
    
    # select decision
    decision_rows <- within_dup_actions %>% filter(Decision_ID == decision)
    
    # identify action type(s)
    retain_temp <- decision_rows %>%
      filter(Action == "Retain" | Action == "Group")

    remove_temp <- decision_rows %>% filter(Action == "Remove")
    
    degroup_temp <- decision_rows %>% filter(Action == "Degroup")
    
    merge_retain_temp <- decision_rows %>% filter(Action == "Merge_and_Retain")
    
    merge_remove_temp <- decision_rows %>% filter(Action == "Merge_and_Remove")
    
    # identify merge template if applicable: 
    merge_template <- unique(decision_rows$Merge_Template)
    merge_template <- trimws(unlist(strsplit(merge_template, ";"))) # split the vector
    
    
    # perform standard action logic --------------------------
    
    retain_records <- master_db_dedup %>%
      semi_join(
        retain_temp,
        by = c("Data_Source" = "Data_Source",
               "Original_Project_ID" = "Original_Project_ID",
               "tier1_dup_key" = "tier1_dup_key"))
    
    remove_records <- master_db_dedup %>%
      semi_join(
        remove_temp,
        by = c("Data_Source" = "Data_Source",
               "Original_Project_ID" = "Original_Project_ID",
               "tier1_dup_key" = "tier1_dup_key")) %>% 
      mutate(Duplicate = 1)
    
    merge_retain_records <- master_db_dedup %>%
      semi_join(
        merge_retain_temp,
        by = c(
          "Data_Source",
          "Original_Project_ID",
          "tier1_dup_key"))
    
    merge_remove_records <- master_db_dedup %>%
      semi_join(
        merge_remove_temp,
        by = c(
          "Data_Source",
          "Original_Project_ID",
          "tier1_dup_key"))  %>% 
      mutate(Duplicate = 1)
    
    # Custom degroup logic ------------------
   
    degroup_records <- master_db_dedup[0, ]     # Create empty data frame to store degrouped records if necessary  
    
    if (nrow(degroup_temp) > 0) {
      
       if (degroup_temp$Project_Name == "Lost River Preserve Restoration") {
        
        # Select full records 
        degroup_records <- master_db_dedup %>%
          semi_join(
            degroup_temp,
            by = c("Data_Source" = "Data_Source",
                   "Original_Project_ID" = "Original_Project_ID",
                   "tier1_dup_key" = "tier1_dup_key"))
        
        # Identify the duplicate rows of Habitat_Type 
        hab_rows <- degroup_records %>% filter(Habitat_Type == "freshwater wetland")
        
        # Sum acres restored for the same habitat 
        acerage_sum <- sum(hab_rows$Acres_Restored, na.rm = TRUE)
        
        # Update the first row and mark the second row as a duplicate: 
        hab_rows[1,] <- hab_rows[1,] %>% mutate(Acres_Restored = acerage_sum)
        hab_rows[2,] <- hab_rows[2,] %>% mutate(Duplicate = 1)
        
        # Update degroup_records
        degroup_records <- degroup_records %>%
          filter(!(Habitat_Type == "freshwater wetland")) %>% 
          bind_rows(hab_rows)
      
      } else if (degroup_temp$Project_Name == "Reef Medics Community-Based Training Program") { 
        
        # Select full records 
        degroup_records <- master_db_dedup %>%
          semi_join(
            degroup_temp,
            by = c("Data_Source" = "Data_Source",
                   "Original_Project_ID" = "Original_Project_ID",
                   "tier1_dup_key" = "tier1_dup_key"))
   
        # Identify the duplicate rows of Habitat_Type 
        hab_rows <- degroup_records %>% filter(Habitat_Type == "hard bottom")
        
        # Sum acres restored for the same habitat 
        acerage_sum <- sum(hab_rows$Acres_Restored, na.rm = TRUE)     
        
        # Update the first row and mark the second row as a duplicate: 
        hab_rows[1,] <- hab_rows[1,] %>% mutate(Acres_Restored = acerage_sum)
        hab_rows[2,] <- hab_rows[2,] %>% mutate(Duplicate = 1)
        
        # Update degroup_records
        degroup_records <- degroup_records %>%
          filter(!(Habitat_Type == "hard bottom")) %>% 
          bind_rows(hab_rows)
        
        
      } else if (degroup_temp$Project_Name == "Egmont Key National Wildlife Refuge Vegetation Management and Dune Retention") {
        
        # Select full records   
        degroup_records <- master_db_dedup %>%
          semi_join(
            degroup_temp,
            by = c("Data_Source" = "Data_Source",
                   "Original_Project_ID" = "Original_Project_ID",
                   "tier1_dup_key" = "tier1_dup_key"))
        
        
        # Identify the duplicate rows of the year 2024:  
        year_rows <- degroup_records %>% filter(Completion_Year == 2024)
        
        # Sum acres restored for the same year (which has the same habitat) 
        acerage_sum <- sum(year_rows$Acres_Restored, na.rm = TRUE)   
        
        
        # Combine the plant types for the same year (which has the same habitat): 
        combined_plant <- unique(year_rows$Plant_Type)
        combined_plant <- combined_plant[!is.na(combined_plant)]
        combined_plant <- paste(combined_plant, collapse = ", ")
        

        
        # Update the first row and mark the second row as a duplicate: 
        year_rows[1,] <- year_rows[1,] %>% mutate(Acres_Restored = acerage_sum,
                                                  Plant_Type = combined_plant)
        year_rows[2,] <- year_rows[2,] %>% mutate(Duplicate = 1)
        
        
        # Update degroup_records: 
        degroup_records <- degroup_records %>% 
          filter(!(Completion_Year == 2024)) %>% bind_rows(year_rows)
        
      
        } 
      
    } else {} # end degroup logic 
    
    
    # perform variable specific merges if applicable: ---------------
    
    if ("Restoration_Technique" %in% merge_template & nrow(degroup_temp) == 0 ) {
      
      combined <- unique(c(merge_retain_records$Restoration_Technique,
                           merge_remove_records$Restoration_Technique))
      
      combined <- combined[!is.na(combined)]
      
      combined <- paste(combined, collapse = ", ")
      
      # update the retained record: 
      merge_retain_records <- merge_retain_records %>%
        mutate(Restoration_Technique = combined) } 
    
    if ("Project_Group_ID" %in% merge_template & nrow(degroup_temp) == 0 ) {
      
      # calculate next available Project_Group_ID
      next_id <- max(master_db_dedup$Project_Group_ID, na.rm = TRUE) + 1               
      
      retain_records <- retain_records %>%
        mutate(Project_Group_ID = next_id) } 
    
    if ("Miles_Restored" %in% merge_template & nrow(degroup_temp) == 0 ) {
      
      # calculate next available Project_Group_ID
      miles_sum <- sum(c(merge_retain_records$Miles_Restored, 
                         merge_remove_records$Miles_Restored), na.rm = TRUE)             
      
      merge_retain_records <- merge_retain_records %>%
        mutate(Miles_Restored = miles_sum) } 
    
    if ("Acres_Restored" %in% merge_template & nrow(degroup_temp) == 0 ) {
      
      # calculate next available Project_Group_ID
      acres_sum <- sum(c(merge_retain_records$Acres_Restored, 
                         merge_remove_records$Acres_Restored), na.rm = TRUE)             
      
      merge_retain_records <- merge_retain_records %>%
        mutate(Acres_Restored = acres_sum)
      
    } else {} # end of merge template logic
    
    # To account for scenarios where Original_Project_ID is the same for all rows: 
    
    if(nrow(merge_retain_records) == 3 && 
      all(merge_retain_records$Project_Name == "Shell Point Beach Nourishment")) {
 
      # Retain the first row and mark the following two as duplicates:      
      merge_retain_records$Duplicate <- c(0, 1, 1)
      
    } else {} # end of specific scenario 
    
    
    # If merge template is specified, add Merged_Record_ID to retained records:
    if (length(merge_template) == 0) {
      
      # no merge template specified, do not update Merged_Record_ID
      
    } else {
      
      
      if (nrow(degroup_temp) > 0 ||( nrow(merge_retain_records) > 0 &&
          all(merge_retain_records$Project_Name == "Shell Point Beach Nourishment"))) {
        
        # Don't do this for degroup cases (all the same original project id)
        # or other scenarios where all the same original project id (e.g., Shell Point Beach Nourishment)
        
    } else {
      merge_retain_records <- merge_retain_records %>%
        mutate(Merged_Record_ID = 
                 paste(merge_retain_records$Original_Project_ID,"_",merge_retain_records$Data_Source,"_",
                       merge_remove_records$Original_Project_ID,"_",merge_remove_records$Data_Source, sep = ""))
      
      }
      
    } # end of merged project id 
    
    
    # Merge retained and removed records back together into master_db_dedup: 
    master_db_dedup <- master_db_dedup %>%
      anti_join(
        bind_rows(retain_records, remove_records, degroup_records, merge_retain_records,merge_remove_records),
        by = c("Data_Source", "Original_Project_ID", "tier1_dup_key")) %>%
      bind_rows(retain_records, remove_records, degroup_records, merge_retain_records, merge_remove_records)
    
  
    
  } # end of decision updates 
  
  # Clear environment of temporary variables:
  rm(retain_records, remove_records, degroup_records, merge_retain_records,
     merge_remove_records, degroup_temp, merge_template, remove_temp, 
     retain_temp, decision_rows, hab_rows, merge_remove_temp, merge_retain_temp, 
     year_rows, combined_plant, acres_sum, miles_sum, next_id)
}

# -----------------------------------------------------------------------------
# HANDLE BETWEEN-DATASET DUPLICATES 
# -----------------------------------------------------------------------------

{

# START WITH THE DATASET WITH THE MOST DUPLICATES ACROSS OTHER DATASETS, AND 
# THEN ITERATE THROUGH THE OTHERS.

# SNAPP has the most duplicates with NEP (339), followed by NOAA (72).
# DWH - DIVER (3) 


# SNAPP VS NEP DUPLICATES --------------------------------------------

{
# Identify SNAPP rows that have matching NEP dup_keys
SNAPP_with_NEP <- master_db_dedup %>%
  filter(Data_Source == "SNAPP") %>%
  semi_join(master_db_dedup %>% filter(Data_Source == "NEP"), by = "tier1_dup_key")

# Count rows per tier1_dup_key and Data_Source
dup_counts <- SNAPP_with_NEP %>%
  bind_rows(master_db_dedup %>% filter(Data_Source == "NEP", tier1_dup_key %in% SNAPP_with_NEP$tier1_dup_key)) %>%
  count(tier1_dup_key, Data_Source) %>%
  pivot_wider(names_from = Data_Source, values_from = n, values_fill = 0)

# Classify keys
dup_counts <- dup_counts %>%
  mutate(
    dup_class = case_when(
    SNAPP == 1 & NEP == 1       ~ "1-to-1",
    SNAPP > 1 | NEP >= 1        ~ "1-to-many",
    TRUE                         ~ "unclassified"
  ))

# Extract keys for each category
dup_exact_1to1_keys       <- dup_counts %>% filter(dup_class == "1-to-1") %>% pull(tier1_dup_key)
dup_multi_SNAPP_keys      <- dup_counts %>% filter(dup_class == "1-to-many") %>% pull(tier1_dup_key)
dup_unclassified_keys     <- dup_counts %>% filter(dup_class == "unclassified") %>% pull(tier1_dup_key)

# Round 1: EXACT MATCH CASE: Update NEP from SNAPP, drop SNAPP -------

# Manually inspect one SNAPP row per one NEP row to confirm variables to update: 
SNAPP_NEP_exact_view <- master_db_dedup %>%
  filter(
    tier1_dup_key %in% dup_exact_1to1_keys,
    Data_Source %in% c("SNAPP", "NEP")) %>%
  mutate(source_order = if_else(Data_Source == "NEP", 1L, 2L)) %>%
  arrange(tier1_dup_key, source_order) %>%
  select(-source_order)

# Review indicates that NEP has all or better resolution information than 
# SNAPP (as SNAPP is static dataset that was pulled from NEP primary data), and
# so SNAPP rows will be for duplicate removal 

# Mark associated rows as duplicates
drop_SNAPP_exact <- master_db_dedup %>%
  filter(Data_Source == "SNAPP",
         tier1_dup_key %in% dup_exact_1to1_keys) %>%
  mutate(Duplicate = 1)


# ROUND 2: MULTI-MATCH CASE: Keep NEP, drop SNAPP ------- 

# Manually inspect one SNAPP row per multi-NEP row to confirm variables to update: 
SNAPP_NEP_multi_view <- master_db_dedup %>%
  filter(
    #Duplicate == 0, # this is to remove the exact 1-to-1 matches that have already been addressed in round 1
    tier1_dup_key %in% dup_multi_SNAPP_keys,
    Data_Source %in% c("SNAPP", "NEP")) %>%
  mutate(source_order = if_else(Data_Source == "NEP", 1L, 2L)) %>%
  arrange(tier1_dup_key, source_order) %>%
  select(-source_order)

# Review indicates that NEP has all or better resolution information than 
# SNAPP (as SNAPP is static dataset that was pulled from NEP primary data), and
# so SNAPP rows will be for duplicate removal 

# Mark associated rows as duplicates
drop_SNAPP_multi <- master_db_dedup %>%
  filter(Data_Source == "SNAPP",
         tier1_dup_key %in% dup_multi_SNAPP_keys) %>%
  mutate(Duplicate = 1)


# Update cleaned master database with updated rows and flag duplicates:------- 
drop_all_SNAPP_NEP <- bind_rows(drop_SNAPP_exact,drop_SNAPP_multi)

master_db_dedup <- master_db_dedup %>%
  rows_update(drop_all_SNAPP_NEP,by = c("Data_Source","Original_Project_ID","tier1_dup_key"))

master_db_dedup %>% filter(Duplicate == 1) %>% nrow() # count number of Duplicate rows 

# Clean environment
rm(SNAPP_with_NEP, dup_counts, dup_exact_1to1_keys, dup_multi_SNAPP_keys,
   dup_unclassified_keys, SNAPP_NEP_exact_view,  drop_SNAPP_exact, 
   SNAPP_NEP_multi_view, drop_all_SNAPP_NEP, drop_SNAPP_multi) 
   
} # end of SNAPP vs NEP 
master_db_dedup %>% filter(Duplicate == 1) %>% nrow() 


# SNAPP VS NOAA DUPLICATES ---------------------------------------
# Complication here compared to NEP is that NOAA and SNAPP both multiple 
# rows for the same project due to the breakdown of habitat types in restoration 
# metrics like Acreage Restored, and current method is doing many to many. 
# Method will group NOAA as total acerage restored for a project and then 
# compare to the sum of SNAPP acreage restored for the same project, to make 
# this as less messy as possible. 

{ 

# Collapse NOAA only for comparison (gives one value per NOAA project)
NOAA_ref <- master_db_dedup %>%
  filter(Data_Source == "NOAA") %>%
  group_by(tier1_dup_key) %>%
  summarise(
    n_NOAA = n(),           # number of rows per SNAPP project
    Acres_Restored_NOAA = sum(Acres_Restored, na.rm = TRUE),
    .groups = "drop")

# Identify SNAPP sums per project group vs NOAA sums per project group, 
# and classify as exact match, multi SNAPP, or unclassified
SNAPP_sum <- master_db_dedup %>%
  filter(Data_Source == "SNAPP") %>%
  group_by(tier1_dup_key) %>%
  summarise(
    Acres_Restored_SNAPP = sum(Acres_Restored, na.rm = TRUE),
    n_SNAPP = n(),           # number of rows per SNAPP project
    .groups = "drop")

proj_compare <- SNAPP_sum %>%
  inner_join(NOAA_ref, by = "tier1_dup_key") %>%
  mutate(
    dup_class = case_when(
      Acres_Restored_SNAPP == Acres_Restored_NOAA ~ "exact_match",
      n_SNAPP > 1 ~ "multi_SNAPP",
      TRUE ~ "unclassified"))

# Round 1: EXACT MATCH CASE: Update NOAA from SNAPP, drop SNAPP -------

# Manually inspect NOAA-SNAPP exact match duplicates to confirm which variables 
# to merge over: 
SNAPP_NOAA_exact_view <- master_db_dedup %>%
  filter(
    tier1_dup_key %in% proj_compare$tier1_dup_key[proj_compare$dup_class == "exact_match"],
    Data_Source %in% c("SNAPP", "NOAA")) %>%
  mutate(source_order = if_else(Data_Source == "NOAA", 1L, 2L)) %>%
  arrange(tier1_dup_key, source_order) %>%
  select(-source_order)

# From manual review, determined that no variables need to be merged over from 
# SNAPP to NOAA (SNAPP obtained data directly from NOAA, therefore NOAA dataset
# is updated and more reliable)

# Mark duplicate rows:
drop_SNAPP_exact <- master_db_dedup %>%
  filter(Data_Source == "SNAPP",
         tier1_dup_key %in% proj_compare$tier1_dup_key[proj_compare$dup_class == "exact_match"]) %>%
  mutate(Duplicate = 1)


# Round 2: NON-EXACT MATCH CASE: Update NOAA from SNAPP, drop SNAPP -------

# Manually inspect NOAA-SNAPP exact match duplicates to confirm which variables 
# to merge over (from multi or unclassified dup class): 
SNAPP_NOAA_multi_view <- master_db_dedup %>%
  filter(
    tier1_dup_key %in% proj_compare$tier1_dup_key[
      proj_compare$dup_class !="exact_match"],
    Data_Source %in% c("SNAPP", "NOAA")) %>%
  mutate(
    source_order = if_else(Data_Source == "NOAA", 1L, 2L)) %>%
  arrange(tier1_dup_key, source_order) %>%
  select(-source_order)

# From manual review, determined that no variables need to be merged over from 
# SNAPP to NOAA (SNAPP obtained data directly from NOAA, therefore NOAA dataset
# is updated and more reliable)

# Mark duplicate rows:
drop_SNAPP_other <- master_db_dedup %>%
  filter(Data_Source == "SNAPP",
         tier1_dup_key %in% proj_compare$tier1_dup_key[proj_compare$dup_class != "exact_match"]) %>%
  mutate(Duplicate = 1)


# Update cleaned master database with updated rows and flagged removal of duplicates:------- 
drop_all_SNAPP_NOAA <- bind_rows(drop_SNAPP_exact,drop_SNAPP_other) 

master_db_dedup <- master_db_dedup %>%
  rows_update(drop_all_SNAPP_NOAA, by = c("Data_Source","Original_Project_ID","tier1_dup_key","Habitat_Type"))

master_db_dedup %>% filter(Duplicate == 1) %>% nrow() # count number of Duplicate rows 

# Clean environment: 
rm("drop_SNAPP_exact", "drop_SNAPP_other", "drop_all_SNAPP_NOAA", 
   "SNAPP_NOAA_multi_view","proj_compare","SNAPP_NOAA_exact_view","SNAPP_sum",
   "NOAA_ref")

} # end of SNAPP vs NOAA
master_db_dedup %>% filter(Duplicate == 1) %>% nrow() 


# DWH VS DIVER DUPLICATES --------------------------------------------

{
# Identify DIVER  rows that have matching DWH dup_keys
DIVER_with_DWH <- master_db_dedup %>%
  filter(Data_Source == "DIVER") %>%
  semi_join(master_db_dedup %>% filter(Data_Source == "DWH"), by = "tier1_dup_key")

# Count rows per dup_key and Data_Source
dup_counts <- DIVER_with_DWH %>%
  bind_rows(master_db_dedup %>% filter(Data_Source == "DWH", tier1_dup_key %in% DIVER_with_DWH$tier1_dup_key)) %>%
  count(tier1_dup_key, Data_Source) %>%
  pivot_wider(names_from = Data_Source, values_from = n, values_fill = 0)

# Classify keys
dup_counts <- dup_counts %>%
  mutate(dup_class = case_when(
    DIVER == 1 & DWH == 1       ~ "1-to-1",
    DIVER > 1 | DWH >= 1        ~ "1-to-many",
    TRUE                         ~ "unclassified"
  ))

# Extract keys for each category
dup_exact_1to1_keys       <- dup_counts %>% filter(dup_class == "1-to-1") %>% pull(tier1_dup_key)
dup_multi_DIVER_keys      <- dup_counts %>% filter(dup_class == "1-to-many") %>% pull(tier1_dup_key)
dup_unclassified_keys     <- dup_counts %>% filter(dup_class == "unclassified") %>% pull(tier1_dup_key)

# Round 1: EXACT MATCH CASE: Update DIVER from DWH, drop DWH -------


# Manually inspect one DIVER row per one DWH row to confirm variables to update: 
DIVER_DWH_exact_view <- master_db_dedup %>%
  filter( tier1_dup_key %in% dup_exact_1to1_keys, Data_Source %in% c("DIVER", "DWH")) %>%
  mutate(source_order = if_else(Data_Source == "DIVER", 1L, 2L)) %>%
  arrange(tier1_dup_key, source_order) %>%
  select(-source_order)

# Review confirms that want to update DIVER from DWH, and drop DWH rows:

# Update the DIVER rows with DWH information 
updated_DIVER <- master_db_dedup %>%
  filter(Data_Source == "DIVER", tier1_dup_key %in% dup_exact_1to1_keys) %>%
  left_join(DIVER_DWH_exact_view %>%
              filter(Data_Source == "DWH") %>%   # keep only DWH rows
              select(
                tier1_dup_key,
                Original_Project_ID_DWH = Original_Project_ID,
                Restoration_Technique_DWH = Restoration_Technique,
                Miles_Restored_DWH = Miles_Restored,
                Funding_Program_DWH = Funding_Program,
                Legislation_DWH = Legislation,
                Legislation_Funding_DWH = Legislation_Funding,
                Total_Project_Cost_DWH = Total_Project_Cost
              ),
            by = "tier1_dup_key"
  ) %>%
  mutate(
    Restoration_Technique = coalesce(Restoration_Technique_DWH, Restoration_Technique),
    Miles_Restored = coalesce(Miles_Restored_DWH, Miles_Restored),
    Funding_Program = coalesce(Funding_Program_DWH, Funding_Program),
    Legislation = coalesce(Legislation_DWH, Legislation),
    Legislation_Funding = coalesce(Legislation_Funding_DWH, Legislation_Funding),
    Total_Project_Cost = coalesce(Total_Project_Cost_DWH, Total_Project_Cost),
    
    Merged_Record_ID = paste(Original_Project_ID, "DIVER",
                              Original_Project_ID_DWH, "DWH", sep = "_"),
    
    Data_Source_2 = "DWH"
  ) %>%
  select(any_of(names(master_db_dedup)), Merged_Record_ID)


# Mark duplicate rows to drop:
drop_exact <- master_db_dedup %>%
  filter(Data_Source == "DWH",
         tier1_dup_key %in% dup_exact_1to1_keys) %>%
  mutate(Duplicate = 1) 



# Round 2: MULTI MATCH CASE: Update DIVER from DWH, drop DWH -------


# Manually inspect multiple DIVER rows per one DWH row to confirm variables to update: 
DIVER_DWH_multi_view <- master_db_dedup %>%
  filter( tier1_dup_key %in% dup_multi_DIVER_keys, Data_Source %in% c("DIVER", "DWH")) %>%
  mutate(source_order = if_else(Data_Source == "DIVER", 1L, 2L)) %>% # order so DIVER first 
  arrange(tier1_dup_key, source_order) %>%
  select(-source_order)

# Review confirms that all the DIVER rows are for the same project (same Orginal_Project_ID but just
# different restoration techniques, so first merge the DIVER rows (just Restoration_Technique only)

# Combine restoration techniques for the duplicate DIVER rows
DIVER_techniques_combined <- DIVER_DWH_multi_view %>%
  filter(Data_Source == "DIVER") %>%
  group_by(tier1_dup_key) %>%
  summarise(
    Restoration_Technique_combined =
      paste(unique(Restoration_Technique[!is.na(Restoration_Technique)]),
            collapse = ", "),
    .groups = "drop")

# Attach this combined value to the first DIVER row
DIVER_combined <- DIVER_DWH_multi_view %>%
  filter(Data_Source == "DIVER") %>%
  group_by(tier1_dup_key) %>%
  slice(1) %>%                     # keep row 1
  ungroup() %>%
  left_join(DIVER_techniques_combined, by = "tier1_dup_key") %>%
  mutate(
    Restoration_Technique = Restoration_Technique_combined
  ) %>%
  select(-Restoration_Technique_combined)

# Update the DIVER row above with DWH information 
updated_DIVER_multi <- DIVER_combined %>%
  filter(tier1_dup_key %in% dup_multi_DIVER_keys) %>%
  left_join(DIVER_DWH_multi_view %>%
              filter(Data_Source == "DWH") %>%   # keep only DWH rows
              select(
                tier1_dup_key,
                Original_Project_ID_DWH = Original_Project_ID,
                Funding_Program_DWH = Funding_Program,
                Legislation_DWH = Legislation,
                Legislation_Funding_DWH = Legislation_Funding,
                Total_Project_Cost_DWH = Total_Project_Cost
              ),
            by = "tier1_dup_key"
  ) %>%
  mutate(
    Funding_Program = coalesce(Funding_Program_DWH, Funding_Program),
    Legislation = coalesce(Legislation_DWH, Legislation),
    Legislation_Funding = coalesce(Legislation_Funding_DWH, Legislation_Funding),
    Total_Project_Cost = coalesce(Total_Project_Cost_DWH, Total_Project_Cost),
    
    Merged_Record_ID = paste(Original_Project_ID, "DIVER",
                              Original_Project_ID_DWH, "DWH", sep = "_"), 
    Data_Source_2 = "DWH") %>%
  select(any_of(names(master_db_dedup)), Merged_Record_ID)



# Mark duplicate rows to drop:
drop_multi <- master_db_dedup %>%
  filter(tier1_dup_key %in% dup_multi_DIVER_keys) %>%
  filter(Duplicate != 1) %>%
  filter(Data_Source == "DWH") %>%
  mutate(Duplicate = 1)  # the other two DIVER rows have already been marked 
  # duplicate by previous within dataset deduplication

# Update cleaned master database with updated rows and flagged removal of duplicates:------- 
drop_all_DIVER_DWH <- bind_rows(drop_exact,drop_multi) 

master_db_dedup <- master_db_dedup %>%
  rows_update(updated_DIVER, by = c("Data_Source","Original_Project_ID","tier1_dup_key")) %>%
  rows_update(updated_DIVER_multi, by = c("Data_Source","Original_Project_ID","tier1_dup_key")) %>%
  rows_update(drop_all_DIVER_DWH, by = c("Data_Source","Original_Project_ID","tier1_dup_key"))


# Clean environment: 
rm("drop_all_DIVER_DWH","drop_exact","drop_multi","DIVER_DWH_multi_view",
   "DIVER_techniques_combined","DIVER_combined","updated_DIVER_multi",
   "updated_DIVER","tier1_key","dup_exact_1to1_keys","dup_multi_DIVER_keys",
   "DIVER_DWH_exact_view","DIVER_with_DWH","dup_counts")


} # end of DIVER vs DWH 

} # end between set duplicates 

# -----------------------------------------------------------------------------
# SUMMARY STATS OF STAGE 1
# -----------------------------------------------------------------------------

# Print the number of duplicate records flagged for stage 1: 
print(paste0("Number of duplicate records flagged in stage 1: ", tier1$total_dup_records))

# Count number of duplicates removed in stage 1
t1_dup_count <- nrow(master_db_dedup %>% filter(Duplicate == 1))

# Print the number of duplicates removed in stage 1: 
print(paste0("Number of duplicate records removed in stage 1: ", t1_dup_count))

# Count number of merged records (not removed) in stage 1
t1_merge_count <- master_db_dedup %>%
  filter(!is.na(Merged_Record_ID), Duplicate != 1) %>% nrow()

# Print the number of duplicates merged in stage 1: 
print(paste0("Number of duplicate records merged in stage 1: ", t1_merge_count))

# Print the number of duplicates retained in stage 1: 
print(paste0("Number of duplicate records retained in stage 1: ", 
             tier1$total_dup_records - sum(t1_merge_count,t1_dup_count)))


# ==============================================================================
# ------------------------------------------------------------------------------
# TIER 2: DUPLICATION KEY: Project_Name 
# ------------------------------------------------------------------------------
# ==============================================================================

# ------------------------------------------------------------------------------
# IDENTIFY POTENTIAL DUPLICATE PROJECTS WITHIN AND BETWEEN DATASETS ---
# ------------------------------------------------------------------------------

{
# Create a duplication matrix key of 'Project Name' to identify potential 
# duplicates across datasets that have not been flagged already by the tier 1
# duplication key above (Latitude, Longitude, Project Name, Project Description) 

# Create tier 1 duplicate key reference for exclusion: 
tier1_ids <- bind_rows(tier1$between_records,tier1$within_records) %>%
  distinct(Data_Source, Original_Project_ID, tier1_dup_key, Habitat_Type) 
  
# Conduct duplicate analysis for tier 2: 
tier2 <- duplicate_analysis(
  data = master_db_dedup %>%
    anti_join(tier1_ids,
      by = c("Data_Source", "Original_Project_ID", "tier1_dup_key", "Habitat_Type")),
  dup_key = Project_Name,
  Proj_Group_ID = FALSE, # not considering duplicates that have a project group id 
  Duplicate = TRUE)  # not considering duplicates that have already been marked from tier 1 


# Add a temporary row identifier (temp_row_id) to master_db_dedup for 
# duplication removal of the following section: 
master_db_dedup <- master_db_dedup %>% mutate(temp_row_id = row_number())

# Tier 1 duplicates to retain ONLY for the purpose of comparison between records
# to account for Project_Group_ID: # Tier 1 records to retain
tier1_keep <- master_db_dedup %>%
  semi_join(tier1_ids, by = c("Data_Source", "Original_Project_ID", "tier1_dup_key", "Habitat_Type")) %>%
  filter(!is.na(Project_Group_ID))

# Create tier 2 duplicate key reference: 
# tier2_key <- master_db_dedup %>%
#   anti_join(tier1_ids, # remove rows already flagged as potential duplicates in tier 1
#             by = c("Data_Source", "Original_Project_ID", "tier1_dup_key", "Habitat_Type")) %>% 
#   filter(Duplicate == 0) %>% 
#   mutate(tier2_dup_key = paste(Project_Name)) 

tier2_key <- bind_rows(master_db_dedup %>%
    anti_join(tier1_ids, # remove rows already flagged as potential duplicates in tier 1
      by = c("Data_Source", "Original_Project_ID", "tier1_dup_key", "Habitat_Type")) %>%
    filter(Duplicate == 0),
  tier1_keep) %>% # keep Project_Group_ID records from tier 1 for comparison
  distinct(temp_row_id, .keep_all = TRUE) %>%
  mutate(tier2_dup_key = Project_Name)

} 

# -----------------------------------------------------------------------------
# HANDLE WITHIN-DATASET DUPLICATES 
# ------------------------------------------------------------------------------

{
# NOTE: Given the focus of tier 2, this is not being reviewed as it should have 
# already been addressed in tier 1 and through script 1 of project grouping. 

# Export the potential within-dataset duplicates for manual review
tier2$within_records %>%
  arrange(Project_Name) %>%
  write.csv(
    file = file.path(getwd(), "Deduplication", "tier2_within_dataset_duplicates_preprocessed.csv"),
    row.names = FALSE)
}

# -----------------------------------------------------------------------------
# HANDLE BETWEEN-DATASET DUPLICATES 
# ------------------------------------------------------------------------------

{
  # Export out to review: 
  tier2$between_records %>%
    arrange(Project_Name) %>%
    write.csv(
      file = file.path(getwd(), "Deduplication", "tier2_between_dataset_duplicates_preprocessed.csv"),
      row.names = FALSE)
  

  library(dplyr)
  library(stringr)
  
  #  DIVER - DWH (48)  
  #  NEP - SNAPP (20) 
  #  NEP - NOAA (20)   
  #  NOAA - SNAPP (16) 
  #  DWH - NFWF_GEBF (4)  
  #  FWC_REEFS - NEP (1) 


# DIVER VS DWH DUPLICATES --------------------------------------------
{
  
  # Identify DIVER rows that have matching DWH dup_keys
  DIVER_with_DWH <- master_db_dedup %>%
    filter(Data_Source == "DIVER") %>%
    semi_join(tier2_key %>% filter(Data_Source == "DWH"), by = "tier2_dup_key")
  
  # Count rows per tier2_dup_key and Data_Source
  dup_counts <- DIVER_with_DWH %>%
    bind_rows(tier2_key %>% filter(Data_Source == "DWH", tier2_dup_key %in% DIVER_with_DWH$tier2_dup_key)) %>%
    count(tier2_dup_key, Data_Source) %>%
    pivot_wider(names_from = Data_Source, values_from = n, values_fill = 0)
  
  # Classify keys
  dup_counts <- dup_counts %>%
    mutate(dup_class = case_when(
      DIVER == 1 & DWH == 1       ~ "1-to-1",
      DIVER > 1 | DWH >= 1        ~ "1-to-many",
      TRUE                         ~ "unclassified"
    ))
  
  # Extract keys for each category
  dup_exact_1to1_keys       <- dup_counts %>% filter(dup_class == "1-to-1") %>% pull(tier2_dup_key)
  dup_multi_DIVER_keys      <- dup_counts %>% filter(dup_class == "1-to-many") %>% pull(tier2_dup_key)
  dup_unclassified_keys     <- dup_counts %>% filter(dup_class == "unclassified") %>% pull(tier2_dup_key)
  
  # Round 1: EXACT MATCH CASE: Update DIVER from DWH, drop DWH -------
  
  
  # Manually inspect one DIVER row per one DWH row to confirm variables to update: 
  DIVER_DWH_exact_view <- tier2_key %>%
    filter( tier2_dup_key %in% dup_exact_1to1_keys, Data_Source %in% c("DIVER", "DWH")) %>%
    mutate(source_order = if_else(Data_Source == "DIVER", 1L, 2L)) %>%
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)
  #View(DIVER_DWH_exact_view)
  
  # Review notes (HR June 18, 2026): 
  # Looks like mostly similar, was not caught in the first round of duplication 
  # because the DIVER Project_Description is 'Not Defined' and DWH has a 
  # description so they did not match. 
  
  # Action: Did not update restoration metrics because DIVER is more reliable 
  # and this keeps it consistent.  
  
  
  # Review confirms that want to update DIVER from DWH, and drop DWH rows:
  
  updated_DIVER <- tier2_key %>%
    filter(Data_Source == "DIVER", tier2_dup_key %in% dup_exact_1to1_keys) %>%
    left_join(
      DIVER_DWH_exact_view %>%
        filter(Data_Source == "DWH") %>%
        select(
          tier2_dup_key,
          Original_Project_ID_DWH = Original_Project_ID,
          Project_Description_DWH = Project_Description,
          Exp_Completion_Year_DWH = Exp_Completion_Year,
          Habitat_Type_DWH = Habitat_Type,
          Restoration_Technique_DWH = Restoration_Technique,
          Legislation_Funding_DWH = Legislation_Funding,
          Total_Project_Cost_DWH = Total_Project_Cost
        ),
      by = "tier2_dup_key"
    ) %>%
    mutate(
      
      # Project Description: only replace if "Not Defined"
      Project_Description = if_else(
        Project_Description == "Not Defined" & !is.na(Project_Description_DWH),
        Project_Description_DWH,
        Project_Description),
      
      # Copy over Exp Completion Year if missing
      Exp_Completion_Year = coalesce(Exp_Completion_Year, Exp_Completion_Year_DWH),
      
      # Copy over Total Project Cost, only if NA
      cost_was_na = is.na(Total_Project_Cost),
      Total_Project_Cost = coalesce(Total_Project_Cost, Total_Project_Cost_DWH),
      
      # Copy over Legislation Funding: only if Total_Project_Cost was NA
      Legislation_Funding = if_else(
        cost_was_na & !is.na(Legislation_Funding_DWH), Legislation_Funding_DWH, 
        Legislation_Funding),
      
      # Copy over Habitat Type, fill only if NA
      Habitat_Type = coalesce(Habitat_Type, Habitat_Type_DWH),
      
      # Combine Restoration Technique 
      Restoration_Technique = case_when(
        
        # If DIVER is NA, then take DWH
        is.na(Restoration_Technique) ~ Restoration_Technique_DWH,
        
        # If both exist, then append non-duplicate values
        !is.na(Restoration_Technique) & !is.na(Restoration_Technique_DWH) ~ {
          diver_vals <- str_split(Restoration_Technique, ",\\s*")[[1]]
          dwh_vals   <- str_split(Restoration_Technique_DWH, ",\\s*")[[1]]
          
          combined <- unique(c(diver_vals, dwh_vals))
          paste(combined, collapse = ", ")
        },
        
        # Otherwise keep original
        TRUE ~ Restoration_Technique
      ),
      
      # Merge IDs
      Merged_Record_ID = paste(
        Original_Project_ID, "DIVER",Original_Project_ID_DWH, "DWH",sep = "_"),
      
      Data_Source_2 = "DWH"
    ) %>%
    select(any_of(names(master_db_dedup)), Merged_Record_ID)
  
  # Mark duplicate rows to drop:
  drop_exact <- tier2_key %>%
    filter(Data_Source == "DWH",
           tier2_dup_key %in% dup_exact_1to1_keys) %>%
    mutate(Duplicate = 1) 
  
  
  # Manually inspect multiple DIVER rows per one DWH row to confirm variables to update: 
  DIVER_DWH_multi_view <- tier2_key %>%
    filter( tier2_dup_key %in% dup_multi_DIVER_keys, Data_Source %in% c("DIVER", "DWH")) %>%
    mutate(source_order = if_else(Data_Source == "DIVER", 1L, 2L)) %>% # order so DIVER first 
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)
  #View(DIVER_DWH_multi_view)
  
  
  # Review confirms that all DWH information is documented in the DIVER rows,
  # except for Exp_Completion_Year, so copy over from DWH: 
  
  updated_DIVER_multi <- tier2_key %>%
    filter(Data_Source == "DIVER", tier2_dup_key %in% dup_multi_DIVER_keys) %>%
    left_join(DIVER_DWH_multi_view %>%
                filter(Data_Source == "DWH") %>%
                select(
                  tier2_dup_key,
                  Original_Project_ID_DWH = Original_Project_ID,
                  Exp_Completion_Year_DWH = Exp_Completion_Year
                ),
              by = "tier2_dup_key"
    ) %>%
    mutate(
      Exp_Completion_Year = coalesce(Exp_Completion_Year, Exp_Completion_Year_DWH), 
      Merged_Record_ID = paste(Original_Project_ID, "DIVER", 
                                Original_Project_ID_DWH, "DWH", sep = "_"),
      Data_Source_2 = "DWH") %>%
    select(any_of(names(master_db_dedup)), Merged_Record_ID)
  
  # Mark duplicate rows to drop:
  drop_multi <- tier2_key %>%
    filter(Data_Source == "DWH",
           tier2_dup_key %in% dup_multi_DIVER_keys) %>%
    mutate(Duplicate = 1) 
  
  
  
  # Update cleaned master database with updated rows and flagged removal of duplicates:------- 
  drop_all_DIVER_DWH <- bind_rows( drop_exact, drop_multi) 
  
  master_db_dedup <- master_db_dedup %>%
    rows_update(updated_DIVER, by = "temp_row_id") %>%
    rows_update(updated_DIVER_multi, by = "temp_row_id") %>%
    rows_update(drop_all_DIVER_DWH, by = "temp_row_id")
  
  
  # Clean environment: 
  rm("drop_all_DIVER_DWH","drop_exact","drop_multi","updated_DIVER",
     "updated_DIVER_multi","DIVER_DWH_multi_view",  "dup_counts", 
     "DIVER_DWH_exact_view", "DIVER_with_DWH", "dup_exact_1to1_keys", 
     "dup_multi_DIVER_keys")

}
                                                                                          
nrow(master_db_dedup %>% filter(Duplicate == 1)) #512

# SNAPP VS NEP DUPLICATES -------------------------------------------- 
{
  
  # Identify  SNAPP–NEP duplicates 
  SNAPP_with_NEP <- master_db_dedup %>%
    filter(Data_Source == "SNAPP") %>%
    semi_join(tier2_key %>% filter(Data_Source == "NEP"), by = "tier2_dup_key")
  
  # Count rows per tier2_dup_key and Data_Source
  dup_counts <- SNAPP_with_NEP %>%
    bind_rows(tier2_key %>% filter(Data_Source == "NEP", tier2_dup_key %in% SNAPP_with_NEP$tier2_dup_key)) %>%
    count(tier2_dup_key, Data_Source) %>%
    pivot_wider(names_from = Data_Source, values_from = n, values_fill = 0)
  
  # Classify keys
  dup_counts <- dup_counts %>%
    mutate(dup_class = case_when(
      SNAPP == 1 & NEP == 1       ~ "1-to-1",
      SNAPP == 1 & NEP > 1        ~ "1-to-many",
      TRUE                        ~ "unclassified"
    ))
  
  # Extract keys for each category
  dup_exact_1to1_keys       <- dup_counts %>% filter(dup_class == "1-to-1") %>% pull(tier2_dup_key)
  dup_multi_NEP_keys      <- dup_counts %>% filter(dup_class == "1-to-many") %>% pull(tier2_dup_key)
  dup_unclassified_keys     <- dup_counts %>% filter(dup_class == "unclassified") %>% pull(tier2_dup_key)
  
  
  # Round 1: EXACT MATCH CASE: --------------------------------
  
  # Manually inspect one SNAPP row per NEP row to confirm variables to update: 
  SNAPP_NEP_exact_view <- tier2_key %>%
    # Keep only keys that were exact matches
    filter(tier2_dup_key %in% dup_exact_1to1_keys) %>%
    # Keep only SNAPP + NEP
    filter(Data_Source %in% c("SNAPP","NEP")) %>%
    # For each key + source, pick only one row
    group_by(tier2_dup_key, Data_Source) %>%
    ungroup() %>%
    # Order so NEP is first
    mutate(source_order = if_else(Data_Source == "NEP", 1L, 2L)) %>%
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)
  #View(SNAPP_NEP_exact_view)
  
  # From manual review, determined that no variables need to be merged over from 
  # SNAPP to NEP
  
  # Mark duplicate rows to drop:
  drop_exact <- tier2_key %>%
    filter(Data_Source == "SNAPP",
           tier2_dup_key %in% dup_exact_1to1_keys) %>%
    mutate(Duplicate = 1) 
  
  
  # Round 2: MULTI-MATCH CASE: -----------------------------------
  
  # Manually inspect to confirm variables to update: 
  SNAPP_NEP_multi_view <- tier2_key %>%
    # Keep only keys that were exact matches
    filter(tier2_dup_key %in% dup_multi_NEP_keys) %>%
    # Keep only SNAPP + NEP
    filter(Data_Source %in% c("SNAPP","NEP")) %>%
    # For each key + source, pick only one row
    group_by(tier2_dup_key, Data_Source) %>%
    ungroup() %>%
    # Order so NEP is first
    mutate(source_order = if_else(Data_Source == "NEP", 1L, 2L)) %>%
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)
  #View(SNAPP_NEP_exact_view)
  
  SNAPP_NEP_multi_view %>% count(Data_Source)
  
  # From manual review, determined that no variables need to be merged over from 
  # SNAPP to NEP
  
  # Mark duplicate rows to drop:
  drop_multi <- tier2_key %>%
    filter(Data_Source == "SNAPP",
           tier2_dup_key %in% dup_multi_NEP_keys) %>%
    mutate(Duplicate = 1) 
  
  
  # Round 3: UNCLASSIFIED CASE: -----------------------------------
  
  # Manually inspect to confirm variables to update: 
  SNAPP_NEP_unclassified_view <- tier2_key %>%
    # Keep only keys that were exact matches
    filter(tier2_dup_key %in% dup_unclassified_keys) %>%
    # Keep only SNAPP + NEP
    filter(Data_Source %in% c("SNAPP","NEP")) %>%
    # For each key + source, pick only one row
    group_by(tier2_dup_key, Data_Source) %>%
    ungroup() %>%
    # Order so NEP is first
    mutate(source_order = if_else(Data_Source == "NEP", 1L, 2L)) %>%
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)
  #View(SNAPP_NEP_exact_view)
  
  SNAPP_NEP_unclassified_view %>% count(Data_Source)
  
  # Given the original sources of the data, the NEP data is likely more accurate 
  # than the SNAPP data, so will keep the NEP rows and drop the SNAPP rows 
  
  # Mark duplicate rows to drop:
  drop_unclassified <- tier2_key %>%
    filter(Data_Source == "SNAPP",
           tier2_dup_key %in% dup_unclassified_keys) %>%
    mutate(Duplicate = 1) 
  
  
  # Update cleaned master database with updated rows and flagged removal of duplicates:------- 
  drop_all_NEP_SNAPP <- bind_rows(drop_exact,drop_unclassified) 
  
  master_db_dedup <- master_db_dedup %>%
    rows_update(drop_all_NEP_SNAPP, by = "temp_row_id")
  
  # Clean environment: 
  rm("drop_all_NEP_SNAPP", "drop_exact", "SNAPP_NEP_exact_view","SNAPP_NEP_multi_view", 
     "SNAPP_with_NEP", "dup_unclassified_keys","drop_unclassified", "SNAPP_NEP_unclassified_view")
  
  nrow(master_db_dedup %>% filter(Duplicate == 1)) 
  
}

nrow(master_db_dedup %>% filter(Duplicate == 1)) #532

# NOAA VS NEP DUPLCIATES --------------------------------------------- 
{
# Identify  NOAA–NEP duplicates 
NOAA_with_NEP <- master_db_dedup %>%
  filter(Data_Source == "NOAA") %>%
  semi_join(tier2_key %>% filter(Data_Source == "NEP"), by = "tier2_dup_key")

# Count rows per tier2_dup_key and Data_Source
dup_counts <- NOAA_with_NEP %>%
  bind_rows(tier2_key %>% filter(Data_Source == "NEP", tier2_dup_key %in% NOAA_with_NEP$tier2_dup_key)) %>%
  count(tier2_dup_key, Data_Source) %>%
  pivot_wider(names_from = Data_Source, values_from = n, values_fill = 0)

# Classify keys
dup_counts <- dup_counts %>%
  mutate(dup_class = case_when(
    NOAA == 1 & NEP == 1       ~ "1-to-1",
    NOAA == 1 & NEP > 1        ~ "1-to-many",
    TRUE                        ~ "unclassified"
  ))

# Extract keys for each category
dup_exact_1to1_keys       <- dup_counts %>% filter(dup_class == "1-to-1") %>% pull(tier2_dup_key)
dup_multi_NEP_keys      <- dup_counts %>% filter(dup_class == "1-to-many") %>% pull(tier2_dup_key)
dup_unclassified_keys     <- dup_counts %>% filter(dup_class == "unclassified") %>% pull(tier2_dup_key)


# Round 1: EXACT MATCH CASE: --------------------------------

# Manually inspect one NOAA row per NEP row to confirm variables to update: 

NOAA_NEP_exact_view <- tier2_key %>%
  # Keep only keys that were exact matches
  filter(tier2_dup_key %in% dup_exact_1to1_keys) %>%
  # Keep only NOAA + NEP
  filter(Data_Source %in% c("NOAA","NEP")) %>%
  # For each key + source, pick only one row
  group_by(tier2_dup_key, Data_Source) %>%
  ungroup() %>%
  # Order so NEP is first
  mutate(source_order = if_else(Data_Source == "NEP", 1L, 2L)) %>%
  arrange(tier2_dup_key, source_order) %>%
  select(-source_order)

# From manual review, determined that NOAA is the higher resolution dataset as 
# the records are from older pre 2006 EPA standardization of the NEP data, 
# so therefore will update the NOAA with some merged variables from NEP and then
# mark the NEP rows as duplicates. 

# Review confirms that want to update NOAA from NEP, and drop NEP rows:

updated_NOAA <- tier2_key %>%
  filter(Data_Source == "NOAA", tier2_dup_key %in% dup_exact_1to1_keys) %>%
  left_join(
    NOAA_NEP_exact_view %>%
      filter(Data_Source == "NEP") %>%
      select(
        tier2_dup_key,
        Original_Project_ID_NEP = Original_Project_ID,
        Lead_Implementer_NEP = Lead_Implementer,
        Habitat_Type_NEP = Habitat_Type,
        Restoration_Technique_NEP = Restoration_Technique,
      ),
    by = "tier2_dup_key") %>%
  mutate(
    
    # Transfer Lead Implementer over to Partner
    Partners = Lead_Implementer_NEP,
    
    # Copy over Habitat Type (determined more specific than NOAA)
    Habitat_Type =  Habitat_Type_NEP,
    
    # Combine Restoration Technique 
    Restoration_Technique = case_when(
      
      # If NOAA is NA, then take NEP
      is.na(Restoration_Technique) ~ Restoration_Technique_NEP,
      
      # If both exist, then append non-duplicate values
      !is.na(Restoration_Technique) & !is.na(Restoration_Technique_NEP) ~ {
        NOAA_vals <- str_split(Restoration_Technique, ",\\s*")[[1]]
        NEP_vals   <- str_split(Restoration_Technique_NEP, ",\\s*")[[1]]
        
        combined <- unique(c(NOAA_vals, NEP_vals))
        paste(combined, collapse = ", ")},
      
      # Otherwise keep original
      TRUE ~ Restoration_Technique),
    
    # Merge IDs
    Merged_Record_ID = paste(
      Original_Project_ID, "NOAA",Original_Project_ID_NEP, "NEP",sep = "_"),
    
    Data_Source_2 = "NEP") %>%
  select(any_of(names(master_db_dedup)), Merged_Record_ID)


# Mark duplicate rows to drop:
drop_exact <- tier2_key %>%
  filter(Data_Source == "NEP",
         tier2_dup_key %in% dup_exact_1to1_keys) %>%
  mutate(Duplicate = 1) 


# Round 2: MULTI-MATCH CASE: -----------------------------------

# Manually inspect to confirm variables to update: 
NOAA_NEP_multi_view <- tier2_key %>%
  # Keep only keys that were exact matches
  filter(tier2_dup_key %in% dup_multi_NEP_keys) %>%
  # Keep only NOAA + NEP
  filter(Data_Source %in% c("NOAA","NEP")) %>%
  # For each key + source, pick only one row
  group_by(tier2_dup_key, Data_Source) %>%
  ungroup() %>%
  # Order so NEP is first
  mutate(source_order = if_else(Data_Source == "NEP", 1L, 2L)) %>%
  arrange(tier2_dup_key, source_order) %>%
  select(-source_order)

NOAA_NEP_multi_view %>% count(Data_Source)

# From manual review, determined that NEP records are higher resolution than the
# single NOAA project, and that no variables need to be merged over from 
# NOAA to NEP. 

# Mark duplicate rows to drop:
drop_multi <- tier2_key %>%
  filter(Data_Source == "NOAA",
         tier2_dup_key %in% dup_multi_NEP_keys) %>%
  mutate(Duplicate = 1) 


# Round 3: UNCLASSIFIED CASE: -----------------------------------

# Manually inspect to confirm variables to update: 
NOAA_NEP_unclassified_view <- tier2_key %>%
  # Keep only keys that were exact matches
  filter(tier2_dup_key %in% dup_unclassified_keys) %>%
  # Keep only NOAA + NEP
  filter(Data_Source %in% c("NOAA","NEP")) %>%
  # For each key + source, pick only one row
  group_by(tier2_dup_key, Data_Source) %>%
  ungroup() %>%
  # Order so NEP is first
  mutate(source_order = if_else(Data_Source == "NEP", 1L, 2L)) %>%
  arrange(tier2_dup_key, source_order) %>%
  select(-source_order)


NOAA_NEP_unclassified_view %>% count(Data_Source)

# The NOAA records are a higher resolution of the NEP record which is a duplicate,
#  so will keep the NOAA records and drop the NEP record 

# Mark duplicate rows to drop:
drop_unclassified <- tier2_key %>%
  filter(Data_Source == "NEP",
         tier2_dup_key %in% dup_unclassified_keys) %>%
  mutate(Duplicate = 1) 


# Update cleaned master database with updated rows and flagged removal of duplicates:------- 
drop_all_NOAA_NEP <- bind_rows(drop_exact,drop_multi,drop_unclassified) 

master_db_dedup <- master_db_dedup %>%
  rows_update(updated_NOAA, by = "temp_row_id") %>%
  rows_update(drop_all_NOAA_NEP, by = "temp_row_id")

# Clean environment: 
rm(NOAA_NEP_exact_view, NOAA_NEP_multi_view, NOAA_NEP_unclassified_view,
  drop_exact, drop_multi, drop_unclassified, drop_all_NOAA_NEP, updated_NOAA,
  NOAA_with_NEP)

nrow(master_db_dedup %>% filter(Duplicate == 1)) 

}

nrow(master_db_dedup %>% filter(Duplicate == 1)) #553

# SNAPP VS NOAA DUPLICATES ---------------------------------------
{
  # Identify  SNAPP–NOAA duplicates 
  SNAPP_with_NOAA <- master_db_dedup %>%
    filter(Data_Source == "SNAPP") %>%
    semi_join(tier2_key %>% filter(Data_Source == "NOAA"), by = "tier2_dup_key")
  
  # Count rows per tier2_dup_key and Data_Source
  dup_counts <- SNAPP_with_NOAA %>%
    bind_rows(tier2_key %>% filter(Data_Source == "NOAA", tier2_dup_key %in% SNAPP_with_NOAA$tier2_dup_key)) %>%
    count(tier2_dup_key, Data_Source) %>%
    pivot_wider(names_from = Data_Source, values_from = n, values_fill = 0)
  
  # Classify keys
  dup_counts <- dup_counts %>%
    mutate(dup_class = case_when(
      SNAPP == 1 & NOAA == 1       ~ "1-to-1",
      SNAPP == 1 & NOAA > 1        ~ "1-to-many",
      TRUE                        ~ "unclassified"
    ))
  
  # Extract keys for each category
  dup_exact_1to1_keys       <- dup_counts %>% filter(dup_class == "1-to-1") %>% pull(tier2_dup_key)
  dup_multi_NOAA_keys      <- dup_counts %>% filter(dup_class == "1-to-many") %>% pull(tier2_dup_key)
  dup_unclassified_keys     <- dup_counts %>% filter(dup_class == "unclassified") %>% pull(tier2_dup_key)
  
  
  # Round 1: EXACT MATCH CASE: -------
  
  # Manually inspect one SNAPP row per NOAA row to confirm variables to update: 
  SNAPP_NOAA_exact_view <- tier2_key %>%
    # Keep only keys that were exact matches
    filter(tier2_dup_key %in% dup_exact_1to1_keys) %>%
    # Keep only SNAPP + NOAA
    filter(Data_Source %in% c("SNAPP","NOAA")) %>%
    # For each key + source, pick only one row
    group_by(tier2_dup_key, Data_Source) %>%
    ungroup() %>%
    # Order so NOAA is first
    mutate(source_order = if_else(Data_Source == "NOAA", 1L, 2L)) %>%
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)

  
  # From manual review, determined that no variables need to be merged over from 
  # SNAPP to NOAA
  
  # Mark duplicate rows to drop:
  drop_exact <- tier2_key %>%
    filter(Data_Source == "SNAPP",
           tier2_dup_key %in% dup_exact_1to1_keys) %>%
    mutate(Duplicate = 1) 
  
  # Round 2: MULTI-MATCH CASE: -----------------------------------
  
  # Manually inspect to confirm variables to update: 
  SNAPP_NOAA_multi_view <- tier2_key %>%
    # Keep only keys that were exact matches
    filter(tier2_dup_key %in% dup_multi_NOAA_keys) %>%
    # Keep only SNAPP + NOAA
    filter(Data_Source %in% c("SNAPP","NOAA")) %>%
    # For each key + source, pick only one row
    group_by(tier2_dup_key, Data_Source) %>%
    ungroup() %>%
    # Order so NOAA is first
    mutate(source_order = if_else(Data_Source == "NOAA", 1L, 2L)) %>%
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)

  
  SNAPP_NOAA_multi_view %>% count(Data_Source)
  
  # From manual review, determined that all flagged SNAPP records were already 
  # addressed in tier 1 (not being shown) and so there is no additional records  
  # to mark as duplicates 
  

  # Round 3: UNCLASSIFIED CASE: -----------------------------------
  
  # Manually inspect to confirm variables to update: 
  SNAPP_NOAA_unclassified_view <- tier2_key %>%
    # Keep only keys that were exact matches
    filter(tier2_dup_key %in% dup_unclassified_keys) %>%
    # Keep only SNAPP + NOAA
    filter(Data_Source %in% c("SNAPP","NOAA")) %>%
    # For each key + source, pick only one row
    group_by(tier2_dup_key, Data_Source) %>%
    ungroup() %>%
    # Order so NOAA is first
    mutate(source_order = if_else(Data_Source == "NOAA", 1L, 2L)) %>%
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)

  
  SNAPP_NOAA_unclassified_view %>% count(Data_Source)
  
  # Given the original sources of the data, the NOAA data is more recently 
  # updated and more accurate than the SNAPP data, so will keep the NOAA rows 
  # and drop the SNAPP rows 
  
  # Mark duplicate rows to drop:
  drop_unclassified <- tier2_key %>%
    filter(Data_Source == "SNAPP",
           tier2_dup_key %in% dup_unclassified_keys) %>%
    mutate(Duplicate = 1) 
  
  
  # Update cleaned master database with updated rows (none) and flagged removal of duplicates:------- 
  drop_all_NOAA_SNAPP <- bind_rows(drop_exact,drop_unclassified) 
  
  master_db_dedup <- master_db_dedup %>%
    rows_update(drop_all_NOAA_SNAPP, by = "temp_row_id")
  
  # Clean environment: 
  rm(drop_exact, drop_unclassified, drop_all_NOAA_SNAPP, dup_counts, 
     dup_exact_1to1_keys, dup_multi_NOAA_keys, dup_unclassified_keys, 
     SNAPP_NOAA_exact_view, SNAPP_NOAA_multi_view, SNAPP_NOAA_unclassified_view,
     SNAPP_with_NOAA)
  
  nrow(master_db_dedup %>% filter(Duplicate == 1)) #571
  
}

nrow(master_db_dedup %>% filter(Duplicate == 1)) #571 
  
# DWH VS NFWF_GEBF DUPLICATES -------------------------------------------- 
{
  
  # Identify  SNAPP–NEP duplicates 
  DWH_with_NFWF_GEBF <- master_db_dedup %>%
    filter(Data_Source == "NFWF_GEBF") %>%
    semi_join(tier2_key %>% filter(Data_Source == "DWH"), by = "tier2_dup_key")
  
  # Count rows per tier2_dup_key and Data_Source
  dup_counts <- DWH_with_NFWF_GEBF %>%
    bind_rows(tier2_key %>% filter(Data_Source == "DWH", tier2_dup_key %in% DWH_with_NFWF_GEBF$tier2_dup_key)) %>%
    count(tier2_dup_key, Data_Source) %>%
    pivot_wider(names_from = Data_Source, values_from = n, values_fill = 0)
  
  # Classify keys
  dup_counts <- dup_counts %>%
    mutate(dup_class = case_when(
      NFWF_GEBF == 1 & DWH == 1       ~ "1-to-1",
      DWH == 1 & NFWF_GEBF > 1        ~ "1-to-many",
      TRUE                        ~ "unclassified"
    ))
  
  # Extract keys for each category
  dup_exact_1to1_keys       <- dup_counts %>% filter(dup_class == "1-to-1") %>% pull(tier2_dup_key)
  dup_multi_NFWF_GEBF_keys      <- dup_counts %>% filter(dup_class == "1-to-many") %>% pull(tier2_dup_key)
  dup_unclassified_keys     <- dup_counts %>% filter(dup_class == "unclassified") %>% pull(tier2_dup_key)
  
  
  # Round 1: EXACT MATCH CASE: -------
  
  # Manually inspect one SNAPP row per NOAA row to confirm variables to update: 
  DWH_NFWF_GEBF_exact_view <- tier2_key %>%
    # Keep only keys that were exact matches
    filter(tier2_dup_key %in% dup_exact_1to1_keys) %>%
    # Keep only NFWF_GEBF + DWH
    filter(Data_Source %in% c("NFWF_GEBF","DWH")) %>%
    # For each key + source, pick only one row
    group_by(tier2_dup_key, Data_Source) %>%
    ungroup() %>%
    # Order so DWH is first
    mutate(source_order = if_else(Data_Source == "DWH", 1L, 2L)) %>%
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)
  
  
  # From manual review, determined that project status, completion year, and 
  # variables need to be merged over from NFWF_GEBF to DWH. 
  # Additionally, if DWH has empty (NA or 0) values for the following variables,
  # the the NFWF_GEBF values will be merged over (county multiple, acres restored, 
  # acres protected, miles restored, miles protected, habitat type). Given that 
  # the DWH data (pulled form project tracker that is regularly updated) is more 
  # recently updated and more accurate than the NFWF_GEBF data (pulled from PDFs), 
  # DWH records will be updated and kept and the NFWF_GEBF records will be dropped. 
  
  # Update the DWH rows with NFWF_GEBF information 
  updated_DWH <- tier2_key %>%
    filter(Data_Source == "DWH", tier2_dup_key %in% dup_exact_1to1_keys) %>%
    left_join(DWH_NFWF_GEBF_exact_view %>%
                filter(Data_Source == "NFWF_GEBF") %>%
                select(tier2_dup_key,
                       Original_Project_ID_NFWF_GEBF = Original_Project_ID,
                       Project_Status_NFWF_GEBF = Project_Status,
                       Restoration_Technique_NFWF_GEBF = Restoration_Technique),
              by = "tier2_dup_key") %>%
    mutate(
      Project_Status = coalesce(Project_Status_NFWF_GEBF, Project_Status),
      Restoration_Technique = coalesce(Restoration_Technique_NFWF_GEBF, Restoration_Technique),
      Merged_Record_ID = paste(Original_Project_ID, "DWH",
                                Original_Project_ID_NFWF_GEBF, "NFWF_GEBF",sep = "_"),
      Data_Source_2 = "NFWF_GEBF") %>%
    select(any_of(names(master_db)),Merged_Record_ID)
  
  
  updated_DWH <- tier2_key %>%
    filter(Data_Source == "DWH",
           tier2_dup_key %in% dup_exact_1to1_keys) %>%
    left_join(
      DWH_NFWF_GEBF_exact_view %>%
        filter(Data_Source == "NFWF_GEBF") %>%
        select(
          tier2_dup_key,
          Original_Project_ID_NFWF_GEBF = Original_Project_ID,
          Project_Status_NFWF_GEBF = Project_Status,
          Completion_Year_NFWF_GEBF = Completion_Year,
          County_Multiple_NFWF_GEBF = County_Multiple,
          Acres_Restored_NFWF_GEBF = Acres_Restored,
          Acres_Protected_NFWF_GEBF = Acres_Protected,
          Miles_Restored_NFWF_GEBF = Miles_Restored,
          Miles_Protected_NFWF_GEBF = Miles_Protected,
          Habitat_Type_NFWF_GEBF = Habitat_Type), by = "tier2_dup_key") %>%
    mutate(
      # Replace with NFWF_GEBF values
      Project_Status = Project_Status_NFWF_GEBF,
      Completion_Year = Completion_Year_NFWF_GEBF,
      
      # Replace only when DWH is missing or zero
      County_Multiple = if_else(
        is.na(County_Multiple) | County_Multiple == 0,
        County_Multiple_NFWF_GEBF,County_Multiple),
      Acres_Restored = if_else(
        is.na(Acres_Restored) | Acres_Restored == 0,
        Acres_Restored_NFWF_GEBF,Acres_Restored),
      Acres_Protected = if_else(
        is.na(Acres_Protected) | Acres_Protected == 0,
        Acres_Protected_NFWF_GEBF,Acres_Protected),
      Miles_Restored = if_else(
        is.na(Miles_Restored) | Miles_Restored == 0,
        Miles_Restored_NFWF_GEBF,Miles_Restored),
      Miles_Protected = if_else(
        is.na(Miles_Protected) | Miles_Protected == 0,
        Miles_Protected_NFWF_GEBF, Miles_Protected),
      Habitat_Type = if_else(
        is.na(Habitat_Type) | Habitat_Type == "",
        Habitat_Type_NFWF_GEBF,Habitat_Type),
      
      Merged_Record_ID = paste(
        Original_Project_ID, "DWH",
        Original_Project_ID_NFWF_GEBF, "NFWF_GEBF",
        sep = "_"),
      Data_Source_2 = "NFWF_GEBF") %>%
    select(any_of(names(master_db_dedup)), Merged_Record_ID)
  
  
  # Mark duplicate rows to drop:
  drop_exact <- tier2_key %>%
    filter(Data_Source == "NFWF_GEBF",
           tier2_dup_key %in% dup_exact_1to1_keys) %>%
    mutate(Duplicate = 1) 
  
  
  # Round 2: MULTI-MATCH CASE: -----------------------------------
  
  # Manually inspect to confirm variables to update: 
  DWH_NFWF_GEBF_multi_view <- tier2_key %>%
    # Keep only keys that were multi matches
    filter(tier2_dup_key %in% dup_multi_NFWF_GEBF_keys) %>%
    # Keep only NFWF_GEBF + DWH
    filter(Data_Source %in% c("NFWF_GEBF","DWH")) %>%
    # For each key + source, pick only one row
    group_by(tier2_dup_key, Data_Source) %>%
    ungroup() %>%
    # Order so DWH is first
    mutate(source_order = if_else(Data_Source == "DWH", 1L, 2L)) %>%
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)
  
  DWH_NFWF_GEBF_multi_view %>% count(Data_Source)
  
  # From manual review, determined that all flagged NFWF_GEBF records are 
  # already included in the DWH data. Since DWH is a Project Tracking Database 
  # and NFWF GEBF was manually compiled from informational PDFs, the DWH data is 
  # likely more accurate for some of these variables, DWH records will kept 
  # and the NFWF_GEBF records will be dropped.  
  
  # Mark duplicate rows to drop:
  drop_multi <- tier2_key %>%
    filter(Data_Source == "NFWF_GEBF",
           tier2_dup_key %in% dup_multi_NFWF_GEBF_keys) %>%
    mutate(Duplicate = 1) 
  
  # Round 3: UNCLASSIFIED CASE: -----------------------------------
  
  # No records were categorized as unclassified 
  
  # Update cleaned master database with updated rows and flagged removal of duplicates:------- 
  drop_all_NFWF_GEBF_DWH <- bind_rows(drop_exact,drop_multi) 
  
  master_db_dedup <- master_db_dedup %>%
    rows_update(updated_DWH, by = "temp_row_id") %>% 
    rows_update(drop_all_NFWF_GEBF_DWH, by = "temp_row_id")
  
  # Clean environment: 
  rm(drop_exact, drop_multi, drop_all_NFWF_GEBF_DWH, updated_DWH, 
     DWH_NFWF_GEBF_multi_view, dup_counts, DWH_with_NFWF_GEBF, 
     DWH_NFWF_GEBF_exact_view)
  
  nrow(master_db_dedup %>% filter(Duplicate == 1)) 
  
}

nrow(master_db_dedup %>% filter(Duplicate == 1)) #583

# FWC_REEFS VS NEP DUPLICATES -------------------------------------------- 
{
  
  # Identify  SNAPP–NEP duplicates 
  NEP_with_FWC_REEFS <- master_db_dedup %>%
    filter(Data_Source == "FWC_REEFS") %>%
    semi_join(tier2_key %>% filter(Data_Source == "NEP"), by = "tier2_dup_key")
  
  # Count rows per tier2_dup_key and Data_Source
  dup_counts <- NEP_with_FWC_REEFS %>%
    bind_rows(tier2_key %>% filter(Data_Source == "NEP", tier2_dup_key %in% NEP_with_FWC_REEFS$tier2_dup_key)) %>%
    count(tier2_dup_key, Data_Source) %>%
    pivot_wider(names_from = Data_Source, values_from = n, values_fill = 0)
  
  # Classify keys
  dup_counts <- dup_counts %>%
    mutate(dup_class = case_when(
      FWC_REEFS == 1 & NEP == 1       ~ "1-to-1",
      FWC_REEFS == 1 & NEP > 1        ~ "1-to-many",
      TRUE                        ~ "unclassified"
    ))
  
  # Extract keys for each category
  dup_exact_1to1_keys       <- dup_counts %>% filter(dup_class == "1-to-1") %>% pull(tier2_dup_key)
  dup_multi_NEP_keys      <- dup_counts %>% filter(dup_class == "1-to-many") %>% pull(tier2_dup_key)
  dup_unclassified_keys     <- dup_counts %>% filter(dup_class == "unclassified") %>% pull(tier2_dup_key)
  
  # Round 1: EXACT MATCH CASE: --------------------------------
   
  # No exact matches 
  
  # Round 2: MULTI CASE: -----------------------------------
  
  # Manually inspect to confirm variables to update: 
  NEP_FWC_REEFS_multi_view <- tier2_key %>%
    # Keep only keys that were multi matches
    filter(tier2_dup_key %in% dup_multi_NEP_keys) %>%
    # Keep only FWC_REEFS + NEP
    filter(Data_Source %in% c("FWC_REEFS","NEP")) %>%
    # For each key + source, pick only one row
    group_by(tier2_dup_key, Data_Source) %>%
    ungroup() %>%
    # Order so NEP is first
    mutate(source_order = if_else(Data_Source == "NEP", 1L, 2L)) %>%
    arrange(tier2_dup_key, source_order) %>%
    select(-source_order)
  
  NEP_FWC_REEFS_multi_view %>% count(Data_Source)
  
  # These are different projects, no updates are needed 
  
  # Round 3: UNCLASSIFIED CASE: -----------------------------------
  
  # No unclassified matches 
  
  # Update cleaned master database with updated rows and flagged removal of duplicates:------- 
  
  # No updates are needed 
  
  # Clean environment
  rm(NEP_FWC_REEFS_multi_view, dup_counts, dup_exact_1to1_keys, 
     dup_multi_NEP_keys, dup_unclassified_keys, NEP_with_FWC_REEFS)
  
  nrow(master_db_dedup %>% filter(Duplicate == 1)) 
  
}

nrow(master_db_dedup %>% filter(Duplicate == 1)) #583 (no updates occurred)  

} # end of between dataset duplicates

# -----------------------------------------------------------------------------
# SUMMARY STATS OF STAGE 2
# -----------------------------------------------------------------------------

# Print the number of duplicate records flagged for stage 2: 
print(paste0("Number of duplicate records flagged in stage 2: ", tier2$total_dup_records))

# Count number of duplicates removed in stage 2
t2_dup_count <- nrow(master_db_dedup %>% filter(Duplicate == 1)) - t1_dup_count

# Print the number of duplicates removed in stage 2: 
print(paste0("Number of duplicate records removed in stage 2: ", t2_dup_count))

# Count number of merged records (not removed) in stage 2
t2_merge_count <- master_db_dedup %>%
  filter(!is.na(Merged_Record_ID),
         Duplicate != 1) %>% nrow() - t1_merge_count

# Print the number of duplicates merged in stage 2: 
print(paste0("Number of duplicate records merged in stage 2: ", t2_merge_count))

# Print the number of duplicates retained in stage 2: 
print(paste0("Number of duplicate records retained in stage 2: ", 
             tier2$total_dup_records - sum(t2_merge_count,t2_dup_count)))

  
# ==============================================================================
# ------------------------------------------------------------------------------
# TIER 3: SELECT REVIEW OF CASE STUDY LARGE RESTORATION PROJECTS
# ------------------------------------------------------------------------------
# ==============================================================================

{
# Select manual review of large, complex multi-year or multi-phase restoration 
# projects in the region as identified by GEI team and stakeholder feedback 
# from from TBEP habitat restoration consortium. 

# Extract all records where Project_Name has 'robinson preserve' in it: 
tier_3_robinson_preserve_records <- master_db_dedup %>%
  filter(str_detect(Project_Name, regex("robinson preserve", ignore_case = TRUE))) %>% 
  mutate(Tier_3_Keyword = "Robinson Preserve")

# Extract all records where Project_Name has 'terra ceia' in it: 
tier_3_terra_ceia_records <- master_db_dedup %>%
  filter(str_detect(Project_Name, regex("terra ceia", ignore_case = TRUE))) %>% 
  mutate(Tier_3_Keyword = "Terra Ceia")

# Extract all records where Project_Name has 'rock ponds' in it: 
tier_3_rock_ponds_records <- master_db_dedup %>%
  filter(str_detect(Project_Name, regex("rock ponds", ignore_case = TRUE))) %>% 
  mutate(Tier_3_Keyword = "Rock Ponds")

# Extract all records where Project_Name has 'clam bayou' in it: 
tier_3_clam_bayou_records <- master_db_dedup %>%
  filter(str_detect(Project_Name, regex("clam bayou", ignore_case = TRUE))) %>% 
  mutate(Tier_3_Keyword = "Clam Bayou")

# Extract all records where Project_Name has 'cockroach bay' in it: 
tier_3_cockroach_bay_records <- master_db_dedup %>%
  filter(str_detect(Project_Name, regex("cockroach bay", ignore_case = TRUE))) %>% 
  mutate(Tier_3_Keyword = "Cockroach Bay")

# Extract all records where Project_Name has 'newman branch' in it: 
tier_3_newman_branch_records <- master_db_dedup %>%
  filter(str_detect(Project_Name, regex("newman branch", ignore_case = TRUE))) %>% 
  mutate(Tier_3_Keyword = "Newman Branch")

# Create a dataframe of all records from the above case study projects for review:
tier_3_case_studies <- bind_rows(
  tier_3_robinson_preserve_records,
  tier_3_terra_ceia_records,
  tier_3_rock_ponds_records,
  tier_3_clam_bayou_records,
  tier_3_cockroach_bay_records,
  tier_3_newman_branch_records)

# Remove if Duplicate = 1: 
tier_3_case_studies <- tier_3_case_studies %>% filter(Duplicate == 0)

# Export for manual review: 
write_csv(tier_3_case_studies, paste0(getwd(),"/Deduplication/tier_3_case_studies_preprocessed.csv"))

# Following review, no de-duplication actions are needed for the following 
# case studies: Clam Bayou, Cockroach Bay, Newman Branch, Robinson Preserve, 
# Rock Ponds and Terra Ceia. 


# Print the number of duplicates flagged in stage 3: 
print(paste0("Number of duplicate records flagged in stage 3: ", nrow(tier_3_case_studies)))

# clean environment: 
rm(tier_3_robinson_preserve_records, tier_3_terra_ceia_records, 
   tier_3_rock_ponds_records, tier_3_clam_bayou_records, 
   tier_3_cockroach_bay_records, tier_3_newman_branch_records, 
   tier_3_case_studies)
}



# Duplication process is complete. 

# Save the de-duplication cleaned database: 
save(master_db_dedup, file = paste(getwd(),"/Florida Estuarine Restoration Database/master_db_dedup.Rdata",sep = ""))

