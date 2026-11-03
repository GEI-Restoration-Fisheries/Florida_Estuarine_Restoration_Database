# ==============================================================================
# ------------------------------------------------------------------------------
# POST-PROCESSING QUALITY CONTROL 
# ------------------------------------------------------------------------------
# ==============================================================================


# ==============================================================================
# ------------------------------------------------------------------------------
# POST-PROCESSING PART 1: DATA REFINEMENT 
# ------------------------------------------------------------------------------
# ==============================================================================

{
  
# Clear environment: 
rm(list = ls())
  
# Reload the de-duplication cleaned database: 
load(paste(getwd(),"/Florida Estuarine Restoration Database/master_db_dedup.RData", sep = ""))
  
 # Load libraries: 
library(tidyverse)

# ------------------------------------------------------------------------------
# Format cleaned master database - add Master_Project_ID
# ------------------------------------------------------------------------------

{
  # Save the cleaned master database as a new object for further processing and 
  # remove temporary variables created for duplication efforts: 
  master_db_cleaned <- master_db_dedup %>% 
    select(-c(tier1_dup_key, tier2_dup_key, 
              t1w_Decision_ID, temp_row_id))
  
  # Count the number of records that are flagged as duplicates: 
  print(paste0("Number of records removed due to duplication: ", 
               nrow(master_db_cleaned %>% filter(Duplicate == 1)))) 
  
  
  # Remove project records that are flagged as duplicates (Duplicate = 1):
  master_db_cleaned <- master_db_cleaned %>% filter(Duplicate == 0) 
  
  # Add new column called "Master_Project_ID" with unique IDs.  This will be 
  # a clean sequence starting at 1, where each project has a unique ID and all 
  # rows in the same Project_Group_ID share the same Master_Project_ID.
  master_db_cleaned <- master_db_cleaned %>%
    mutate(group = if_else(
      is.na(Project_Group_ID),
      paste0("row_", row_number()),
      paste0("group_", Project_Group_ID))) %>%
    mutate( Master_Project_ID = match(group, unique(group))) %>%
    select(-group) %>% 
    relocate(Master_Project_ID, .before = Project_Group_ID)
  
  #length(unique(master_db_cleaned$Master_Project_ID))
  
}

# ------------------------------------------------------------------------------
# Standardize Project_Status variable 
# ------------------------------------------------------------------------------ 

{
  # Recategorize inputs of Project_Status to standardize into the following 
  # categories: Active, Completed, Monitoring/O&M, Planning, NA 
  
  master_db_cleaned <- master_db_cleaned %>%
    mutate(
      Project_Status = case_when(
        Project_Status %in% c("In Progress", "Implementation", "Awarded, Amended", "Awarded") ~ "Active",
        Project_Status %in% c("Closed", "Unknown-Acreage reported complete", "Complete") ~ "Completed",
        Project_Status %in% c("Monitoring","Monitoring/O&M") ~ "O&M/Monitoring",
        TRUE ~ Project_Status))
  
  # Replace records that have Project_Status as "O&M/Monitoring" and also a 
  # Completion Year (not NA) to 'Complete':
  master_db_cleaned <- master_db_cleaned %>%
    mutate(Project_Status = ifelse(Project_Status == "O&M/Monitoring" & 
                                     !is.na(Completion_Year), "Completed", Project_Status))
  
  review <- master_db_cleaned %>% filter(Project_Status == "O&M/Monitoring")
  
  # Review categories of of Project Status: 
  review_project_status <- master_db_cleaned %>% 
    group_by(Project_Status) %>% 
    summarise(N_Projects = n_distinct(Master_Project_ID, na.rm = TRUE)) %>%
    mutate(Percent_Projects = paste0(round(N_Projects / n_distinct(master_db_cleaned$Master_Project_ID, na.rm = TRUE) * 100, 1),"%"))
  
}
  
# ------------------------------------------------------------------------------
# Standardize Restoration_Technique variable 
# ------------------------------------------------------------------------------ 

{

# For Restoration_Technique, remove "NA" from comma-separated lists,
# including any associated comma and space: 
master_db_cleaned <- master_db_cleaned %>%
  mutate(Restoration_Technique = Restoration_Technique %>%
           str_remove(", NA$") %>%
           str_remove("^NA, ") %>%
           str_remove("^NA$"))
}

# ------------------------------------------------------------------------------
# Update size categories for variables Acres_Restored and Miles_Restored and  
# create project-level quantitative and categorical variables 
# ------------------------------------------------------------------------------

{
  # Since merging of project records occurred, need to update the size categorical 
  # bins for Acres_Restored and Miles_Restored to reflect the updated values.
  
  # Update size categorical bins for acres and miles restored: 
  master_db_cleaned <- master_db_cleaned %>%
    mutate(
      Miles_Restored = ifelse(Miles_Restored == 0, NA, Miles_Restored),
      Miles_Restored_Category = case_when(
        Miles_Restored > 0 & Miles_Restored < 1 ~ "Less than 1",     # <1 miles
        Miles_Restored >= 1 & Miles_Restored < 5 ~ "1 - 5",          # 1-5 miles
        Miles_Restored >= 5 ~ "5 or more",                           # 5+ miles
        TRUE ~ NA_character_ ), # for any missing or invalid values
      Acres_Restored_Category = case_when(
        Acres_Restored > 0 & Acres_Restored < 1 ~ "Less than 1",     # <1 acres
        Acres_Restored >= 1 & Acres_Restored < 5 ~ "1 - 5",          # 1 - <5 acres
        Acres_Restored >= 5 & Acres_Restored < 50 ~ "5 - 50",        # 5- <50 acres
        Acres_Restored >= 50 ~ "50 or more",                         # 50+ acres
        TRUE ~ NA_character_ ))  %>% # for any missing or invalid values  
    relocate(Acres_Restored_Category, Miles_Restored_Category, .after = Miles_Protected)
  
  # Replace all values of 0 in Miles_Restored with NA value as zeros are not
  # meaningful here: 
  master_db_cleaned <- master_db_cleaned %>%
    mutate(Miles_Restored = ifelse(Miles_Restored == 0, NA, Miles_Restored))
  
  
  # These variables represent record-level information. 
  
  # Create new variables that represent project-level information for 
  # Acres_Restored, Acres_Protected, Miles_Restored, and Miles_Protected: 
  master_db_cleaned <- master_db_cleaned %>%
    group_by(Master_Project_ID) %>%
    mutate(
      Project_Acres_Restored = sum(Acres_Restored, na.rm = TRUE),
      Project_Acres_Protected = sum(Acres_Protected, na.rm = TRUE),
      Project_Miles_Restored = sum(Miles_Restored, na.rm = TRUE),
      Project_Miles_Protected = sum(Miles_Protected, na.rm = TRUE)) %>%
    ungroup() %>% 
    relocate(Project_Acres_Restored, Project_Acres_Protected, 
             Project_Miles_Restored, Project_Miles_Protected, 
             .after = Miles_Protected)
  
  # Create new variables that represent project-level information for the 
  # Acres_Restored_Category and Miles_Restored_Category:
  master_db_cleaned <- master_db_cleaned %>%
    group_by(Master_Project_ID) %>%
    mutate(
      Project_Acres_Restored_Category = case_when(
        Project_Acres_Restored > 0 & Project_Acres_Restored < 1 ~   "Less than 1",  # <1 acres
        Project_Acres_Restored >= 1 & Project_Acres_Restored < 5 ~  "1 - 5",        # 1 - <5 acres
        Project_Acres_Restored >= 5 & Project_Acres_Restored < 50 ~ "5 - 50",       # 5- <50 acres
        Project_Acres_Restored >= 50 ~ "50 or more",                                # 50+ acres
        TRUE ~ NA_character_ ),
      Project_Miles_Restored_Category = case_when(
        Project_Miles_Restored > 0 & Project_Miles_Restored < 1 ~ "Less than 1",   # <1 miles
        Project_Miles_Restored >= 1 & Project_Miles_Restored < 5 ~ "1 - 5",        # 1-5 miles
        Project_Miles_Restored >= 5 ~ "5 or more",                                 # 5+ miles
        TRUE ~ NA_character_ )) %>%
    ungroup() %>% 
    relocate(Project_Acres_Restored_Category, Project_Miles_Restored_Category, 
             .after = Miles_Restored_Category)
  

# Reformat so all the categories are factors: 
master_db_cleaned <- master_db_cleaned %>% 
  mutate(Acres_Restored_Category = factor(Acres_Restored_Category, levels = c("Less than 1","1 - 5","5 - 50","50 or more")),
         Miles_Restored_Category = factor(Miles_Restored_Category, levels = c("Less than 1","1 - 5","5 or more")),
         Project_Acres_Restored_Category = factor(Project_Acres_Restored_Category, levels = c("Less than 1","1 - 5","5 - 50","50 or more")),
         Project_Miles_Restored_Category = factor(Project_Miles_Restored_Category, levels = c("Less than 1","1 - 5","5 or more")))
  
}

# ------------------------------------------------------------------------------
#  Create project-level variable for Habitat_Type 
# ------------------------------------------------------------------------------

{
  # Calculate the number of unique Habitat_Types for a given Master_Project_ID and 
  # create new variable called Project_n_Habitat_Types: 
  master_db_cleaned <- master_db_cleaned %>% 
    group_by(Master_Project_ID) %>%
    mutate(Project_n_Habitat_Types = n_distinct(Habitat_Type)) %>%
    ungroup() %>% 
    relocate(Project_n_Habitat_Types, .after = Habitat_Type)
}

# ------------------------------------------------------------------------------
#  Create project-level variable for Completion_Year
# ------------------------------------------------------------------------------

{
  master_db_cleaned <- master_db_cleaned %>% 
    group_by(Master_Project_ID) %>%
    mutate(Project_Completion_Year = if (all(is.na(Completion_Year))) 
    {NA_real_} else {max(Completion_Year, na.rm = TRUE)}) %>%
    ungroup() %>%
    relocate(Project_Completion_Year, .after = Completion_Year)
}
  
# ------------------------------------------------------------------------------
#  Updates following discussions with working group
# ------------------------------------------------------------------------------
  
{
# Following discussion, the working group ultimately decided to exclude
# projects focused primarily on access or public recreation that did not involve
# direct habitat restoration. These projects generally contained less
# information due to the original data acquisition process and ultimately did
# not align with the primary objectives of the database. These projects may be
# incorporated in future versions of the database.
  
# The two data sources that included many access projects were DIVER & DWH. 

# Review all projects where Restoration_Technique is exclusively labeled as 
# 'education/recreation': 
ed_rec_review <- master_db_cleaned %>% filter(Restoration_Technique == "education/recreation")

# Following review, determined that all projects should flagged exclusively as
# "education/recreation" for Restoration_Technique should be removed. This is
# conducted in the following section: POST-PROCESSING - FINAL CLEANING AND
# FILTERING
  
  
# Review DIVER projects (included many access projects): 
DIVER_review <- master_db_cleaned  %>% filter(Data_Source == "DIVER")
DIVER_review_sub <- DIVER_review %>% filter(Restoration_Technique != "education/recreation" | 
                                              is.na(Restoration_Technique)) %>% 
                                     select(Master_Project_ID, 
                                              Data_Source,
                                              Project_Name, 
                                              Restoration_Technique, 
                                              Project_Acres_Restored, 
                                              Project_Description, 
                                              Not_HabRest,
                                              Notes)
  
# Following review, determined that should remove all projects from Data_Source
# = DIVER (already excluded 'education/recreation' exclusive projects) when
# Not_HabRest = 1; except for Master_Project_ID = 42 and 60 (predation control,
# not exclusively access focused) and Master__Project_ID = 1 and 29 and 45 and
# 38 (are habitat restoration). This is conducted in the following section:
# POST-PROCESSING - FINAL CLEANING AND FILTERING

# Change specific project status from O&M/Monitoring to Complete: 
updated_record <- master_db_cleaned %>% filter(Project_Name == 
                    "Alligator Lake Coastal Dune Lake Hydrologic Restoration") %>% 
                    mutate(Project_Status = "Complete",
                           Completion_Year = "2025",
                           Project_Completion_Year = "2025")


# Change specific project status from O&M/Monitoring to Complete
master_db_cleaned <- master_db_cleaned %>%
  mutate(
    Project_Status = if_else(
      Project_Name == "Alligator Lake Coastal Dune Lake Hydrologic Restoration",
      "Completed", Project_Status),
    Completion_Year = if_else(
      Project_Name == "Alligator Lake Coastal Dune Lake Hydrologic Restoration",
      2025, Completion_Year),
    Project_Completion_Year = if_else(
      Project_Name == "Alligator Lake Coastal Dune Lake Hydrologic Restoration",
      2025, Project_Completion_Year))


# Review DWH projects (included many access projects): 
DWH_review <- master_db_cleaned %>% filter(Data_Source == "DWH") 

DWH_review_sub <- DWH_review %>% filter(Restoration_Technique != "education/recreation" | 
                                          is.na(Restoration_Technique)) %>% 
                                 select(Master_Project_ID, 
                                            Data_Source,
                                            Data_Source_2,
                                            Project_Name, 
                                            Restoration_Technique, 
                                            Project_Description, 
                                            Project_Acres_Restored, 
                                            Project_Miles_Restored,
                                            Project_Acres_Protected,
                                            Project_Miles_Protected)

# Following review, determined that the following projects from Data_Source
# = DWH (already excluded 'education/recreation' exclusive projects) should be
# excluded: 71 (this is an overview of projects that have not clearly been 
# funded/implemented and additionally these projects would be captured in the 
# NEP dataset), 110, 120, 123 (not habitat restoration, all sea turtle focused); 
# 141, 147 (notified by DIVER staff that these two projects had been terminated)


# Rename the category "SAV" to "submerged aquatic vegetation" in the "Habitat
# Type" variable: 

master_db_cleaned <- master_db_cleaned %>% 
  mutate(Habitat_Type = case_when(
    Habitat_Type == "sav" ~ "submerged aquatic vegetation",
    TRUE ~ Habitat_Type))

#unique(master_db_cleaned$Habitat_Type)

}
  
# ------------------------------------------------------------------------------
#  Updates following feedback and discussions from data providers 
# ------------------------------------------------------------------------------  

{
# Rename the variable "Total_Project_Cost" to "Reported_Project_Cost": 
master_db_cleaned <- master_db_cleaned %>% 
                     rename(Reported_Project_Cost = Total_Project_Cost)
  
# Rename the variable "Legislation" to "Funding_Authority": 
master_db_cleaned <- master_db_cleaned %>% 
                     rename(Funding_Authority = Legislation) 

# Rename the variable "Legislation_Funding" to "Funding_Authority_Amount": 
master_db_cleaned <- master_db_cleaned %>% 
                     rename(Funding_Authority_Amount = Legislation_Funding) 
}
  
# clean environment except for master_db_cleaned:
#rm(list = setdiff(ls(), "master_db_cleaned"))
  
} # end of part 1

# ==============================================================================
# ------------------------------------------------------------------------------
# POST-PROCESSING PART 2: SPATIAL FRAMEWORK (GEOGRAPHIC BOUNDS)
# ------------------------------------------------------------------------------
# ==============================================================================

{
# load libraries
library(sf)
library(dplyr)

# Load spatial shapefiles: 
counties_sf <- st_read(paste(getwd(),"/Shapefiles/Counties/Counties_NNC_area.shp", sep = ""))  
boundary_sf <- st_read(paste(getwd(),"/Shapefiles/NNC_area/NNC_area.shp", sep = "")) 
eda_sf <- st_read(paste(getwd(),"/Shapefiles/FL_EDA_NNC_boundary_estuaries/FL_EDA_NNC_boundary_estuaries.shp", sep = ""))

# Create temporary temp_row_id variable:
master_db_cleaned <- master_db_cleaned %>%
  mutate(temp_row_id = row_number()) 

# Create spatial database:  
master_sf <- master_db_cleaned %>%
  filter(!is.na(Latitude) & !is.na(Longitude)) %>%
  st_as_sf(coords = c("Longitude", "Latitude"), crs = 4326, remove = FALSE) %>% # WGS84

  # Keep track of whether County was originally missing
  mutate(County_was_na = is.na(County))



# ------------------------------------------------------------------------------
#  Assign spatial labels 
# ------------------------------------------------------------------------------

{
# Assign spatial labels: 

master_sf <- master_sf %>%
  
  # Record whether County was originally NA
  mutate(County_was_na = is.na(County)) %>%
  
  # Assign county names
  st_transform(st_crs(counties_sf)) %>%
  st_join(counties_sf %>% select(county_name = Name),left = TRUE) %>%
  
  # Assign estuarine discharge areas
  st_transform(st_crs(eda_sf)) %>%
  st_join(eda_sf %>% select(eda_name = Name),left = TRUE) %>%
  
  # Transform to database spatial boundary CRS
  st_transform(st_crs(boundary_sf))

}

# ------------------------------------------------------------------------------
#  Format and add binary flag variables 
# ------------------------------------------------------------------------------

{

# Format temp variable county_name correctly to match current formatting in 
# restoration database: 
master_sf <- master_sf %>%
  mutate(
    # Format GIS-derived county name
    county_name = str_to_title(county_name), # make lowercase except for the first letter of a word
    county_name = str_remove_all(county_name, "\\bCount(y|ies)\\b"), # remove term County or Counties anywhere
    county_name = str_replace_all(county_name, ";", ","), # replace ; with , 
    county_name = str_replace_all(county_name, "\\s+And\\s+", ","), # replace "and" with comma
    county_name = str_replace_all(county_name, ",{2,}", ", "), # remove double commas created by cleaning
    county_name = str_replace_all(county_name, "\\s+,", ","), # remove spaces before commas
    county_name = str_squish(county_name), # trim whitespace
    county_name = str_remove_all(county_name, "^,|,$"),  # remove leading/trailing commas
    
    # Assign a value to the variable County only if there is no county name already 
    # in the database (e.g., NA). Assign a flag to indicate which records were
    # assigned a value from GIS: 
    County = if_else(
      County_was_na & !is.na(county_name),
      county_name,
      County),
    
    # Assign a flag to records outside spatial boundary: 
    County_GIS = if_else(
      County_was_na & !is.na(county_name), 1L, 0L))

# Assign a flag to records outside spatial boundary: 
master_sf <- master_sf %>%
  mutate(Outside_Bounds = if_else(
      lengths(st_intersects(geometry, boundary_sf)) > 0, 0L,1L))

# Rename EDA variable: 
master_sf <- master_sf %>% rename(EDA = eda_name)


# Remove geometry column to return to a regular dataframe:
master_sf <- master_sf %>% st_drop_geometry()


# Merge back with the master_db_cleaned dataset to retain all rows (including
# those which did not have coordinates associated with them):

master_db_final <- master_db_cleaned %>%
  left_join(master_sf %>%
      select(
        temp_row_id,
        County_updated = County,
        EDA,
        County_GIS,
        Outside_Bounds),
    by = "temp_row_id") %>%
  mutate(
    County = coalesce(County_updated, County)) %>%
  select(-County_updated)

# Remove temp_row_id: 
master_db_final <- master_db_final %>% select(-temp_row_id)

}


} # end of part 2

# ==============================================================================
# ------------------------------------------------------------------------------
# POST-PROCESSING PART 3: DATA QUALITY SCREENING
# ------------------------------------------------------------------------------
# ==============================================================================

{
  
# A data quality screening for each subset of standardized records retained from
# the original data sources. For each subset, the completeness of key project
# variables and the suitability of the available information were reviewed to
# determine whether sufficient information was available to support reliable
# representation within the database. Consideration was also given to the
# ability to verify, maintain and update project specific information over time.

# Two source subsets were identified for further review during this screening: 
#    - FDEP 
#    - SNAPP 

# Review FDEP projects: 
FDEP_review <- master_db_final %>% filter(Data_Source == "FDEP") 

# Following review, the associated records were ultimately excluded because the
# available source variables did not sufficiently align with the standardized
# database structure and overarching database objectives

# Review SNAPP projects: 
SNAPP_review <- master_db_final %>% filter(Data_Source == "SNAPP")

# SNAPP subset was flagged as the majority of its records had been identified as
# duplicates of or merged with records of other primary data sources, and the
# remaining records contained limited information. Given that the data source
# was a static, secondary source used primarily to identify potentially missing
# datasets, the remaining records were ultimately excluded because the available
# information was insufficient to support consistent representation and future
# maintenance within the database

} # end of part 3

# ==============================================================================
# ------------------------------------------------------------------------------
# POST-PROCESSING - FINAL CLEANING AND FILTERING
# ------------------------------------------------------------------------------
# ==============================================================================

{

# ------------------------------------------------------------------------------
#  Remove records identified for exclusion in the data refinement  
# ------------------------------------------------------------------------------

  {
# Count the number of records that are terminated or in planning: 
print(paste0("Number of records that are terminated or in planning: ", 
              nrow(master_db_final %>% filter(Project_Status == "Terminated" 
                                                | Project_Status == "Planning"))))
  
term_plan <- master_db_final %>% filter(Project_Status == "Terminated" | 
                                            Project_Status == "Planning")
  
# Remove any remaining projects that has Project_Status as Terminated (not
# exluding projects that don't have a project status). Note: 
# this was intentionally not done during script 1 in order to preserve the 
# ability to identify duplicates that may have been marked as Terminated in 
# other databases (eg project status unknown): 
master_db_final <- master_db_final %>% 
    filter(!Project_Status %in% c("Terminated","Planning") | is.na(Project_Status))
  

# Remove all projects when Restoration_Technique is exclusively labeled as 
# 'education/recreation': 
ed_rec_exclude <- master_db_final %>% filter(Restoration_Technique == "education/recreation")

master_db_final <- master_db_final %>% filter(!(Master_Project_ID %in% 
                                                  ed_rec_exclude$Master_Project_ID))


# Count the number of records removed as access only - not habitat restoration 
# component to the project (see data refinement section above for more details): 
print(paste0("Number of records excluded as education/recreation exclusively: ", 
             nrow(ed_rec_exclude)))


# Remove all projects from Data_Source = DIVER when Not_HabRest = 1; except for
# select Master_Project_ID identified in data refinement section (above):

DIVER_exclude <- master_db_final %>% filter(Data_Source == "DIVER" & 
                                           (Restoration_Technique != "education/recreation" | 
                                            is.na(Restoration_Technique)) & 
                                            Not_HabRest == 1 & 
                                            !Master_Project_ID %in% c(1,29,38,42,45,60))


master_db_final <- master_db_final %>% filter(!(Data_Source == "DIVER" & 
                                                Master_Project_ID %in% 
                                                DIVER_exclude$Master_Project_ID))

# Count the number of records removed as access only - not habitat restoration 
# component to the project from the DIVER dataset that had not already been 
# excluded by the education/recreation filtering (see data refinement section 
# above for more details): 
print(paste0("Number of records excluded additionally from DIVER: ", 
             nrow(DIVER_exclude)))

# Remove all projects from Data_Source = DWH that were identified in the data 
# refinement section (above):

DWH_exclude <- master_db_final %>% filter(Data_Source == "DWH" & 
                                          Master_Project_ID %in% c(71,110,120,123,141,147))

master_db_final <- master_db_final %>% filter(!(Data_Source == "DWH" & 
                                                  Master_Project_ID %in% 
                                                  DWH_exclude$Master_Project_ID))

# Count the number of records removed from the DWH dataset that had not already
# been excluded by the education/recreation filtering (see data refinement
# section above for more details):
print(paste0("Number of records excluded additionally from DWH: ", 
             nrow(DWH_exclude)))


# Count the total number of projects excluded during data refinement:
print(paste0("Total number of records removed due to data refinement: ", 
             sum(nrow(term_plan), nrow(ed_rec_exclude), nrow(DIVER_exclude), 
                 nrow(DWH_exclude))))

  }
  
# ------------------------------------------------------------------------------
#  Remove records identified for exclusion in the data quality screening 
# ------------------------------------------------------------------------------

  {
# Count the number of records that were removed: 
print(paste0("Number of records removed due to data quality screening: ", 
               nrow(master_db_final %>% filter((Data_Source == "FDEP" | Data_Source == "SNAPP"))))) 

# Remove records: 
master_db_final <- master_db_final %>% 
                    filter(!(Data_Source == "FDEP" | Data_Source == "SNAPP"))
  } 
  
# ------------------------------------------------------------------------------
#  Filter out records with no coordinates and remove temp_row_id variable 
# ------------------------------------------------------------------------------

  {
# Count the number of records that fall outside spatial boundary: 
print(paste0("Number of records removed due to outside spatial boundary: ", 
             nrow(master_db_final %>% filter(Outside_Bounds == 1))))

# Remove projects that fall outside spatial boundary (e.g., Outside Bounds ==1):
master_db_final <- master_db_final %>% filter(Outside_Bounds != 1 | is.na(Outside_Bounds))

# Review records where there are no coordinates:
no_coords <- master_db_final %>% filter(is.na(Latitude) | is.na(Longitude)) 

# Count the number of records that with no coordinates: 
print(paste0("Number of records removed due to no coordinates: ", 
             nrow(master_db_final %>% filter(is.na(Outside_Bounds))))) 

# Remove projects that have no coordinates: 
master_db_final <- master_db_final %>% filter(!is.na(Outside_Bounds))

  } 
  
# ------------------------------------------------------------------------------
#  Tidy up the database (e.g., special characters, sentence case etc.)
#------------------------------------------------------------------------------
 
  {
  
# Create temporary unique row number so individual rows can be tracked/matched
master_db_final <- master_db_final %>%  mutate(Row = row_number())
  
#### ------- 1. Project Name  ####

# Some special characters are causing coding issues (e.g., Joe's Bayou ==Joe‚Äôs Bayou)

# Function to fix 
fix_mojibake <- function(x) {
  needs_fix <- grepl("‚Ä", x, fixed = TRUE)
  
  safe_convert <- function(s) {
    out <- tryCatch(iconv(s, from = "UTF-8", to = "macroman"), error = function(e) NA_character_)
    if (is.na(out)) return(s)   # couldn't safely convert — leave it untouched rather than error
    Encoding(out) <- "UTF-8"
    out
  }
  
  x[needs_fix] <- vapply(x[needs_fix], safe_convert, character(1), USE.NAMES = FALSE)
  x <- gsub("\u200B", "", x)    # strip invisible zero-width spaces everywhere
  x
}

# Apply to field
master_db_final$Project_Name <- fix_mojibake(master_db_final$Project_Name)


#### ------- 2. Habitat Type  #### 

# Rename and apply sentence case
master_db_final <- master_db_final %>%
  mutate(Habitat_Type = ifelse(is.na(Habitat_Type), "Unknown", 
                               ifelse(Habitat_Type == "mix (estuarine with freshwater and/or upland)", "Estuarine with freshwater and/or upland",
                                      ifelse(Habitat_Type == "mix (freshwater and upland)", "Upland and freshwater", str_to_sentence(Habitat_Type))))) %>%
  mutate(Habitat_Type = factor(Habitat_Type, levels = c("Coastal upland","Coastal wetland","Estuarine","Estuarine with freshwater and/or upland",
                                                        "Estuarine shoreline","Freshwater wetland","Hard bottom",
                                                        "Mangroves","Mud/sand","Oysters","Salt marsh","Shell bottom",
                                                        "Submerged aquatic vegetation","Tidal tributary/creek/river","Upland",
                                                        "Upland and freshwater","Water column","Other","Unknown")))
  
#### ------- 3. Restoration Technique  ####

# Rename and apply sentence case
master_db_final <- master_db_final %>%
  mutate(Restoration_Technique = ifelse(is.na(Restoration_Technique), "Unknown",
                                        ifelse(Restoration_Technique == "NA, hydrologic restoration", "Unknown, Hydrologic restoration", Restoration_Technique))) %>%
  mutate(Restoration_Technique = Restoration_Technique %>%
           str_split(", ") %>%
           map_chr(~ str_c(str_to_sentence(.x), collapse = ", ")))    
  
  
#### ------- 4. Main Funding Category  ####

# Rename
master_db_final <- master_db_final %>%
  mutate(Main_Funding_Category = ifelse(is.na(Main_Funding_Category), "Unknown",
                                        ifelse(Main_Funding_Category == "Mixed-Partner", "Mixed-partner", 
                                               ifelse(Main_Funding_Category == "Nonprofit / NGO", "NGO/Nonprofit", Main_Funding_Category)))) %>%
  mutate(Main_Funding_Category = factor(Main_Funding_Category, levels = c("Federal","State","Regional","Local",
                                                                          "NGO/Nonprofit","Academic","Private",
                                                                          "NRDA Settlement","Mixed-partner","Other","Unknown")))
  

#### ------- 5. Lead Implementer Category  ####

# Rename
master_db_final <- master_db_final %>%
  mutate(Lead_Implementer_Category = ifelse(is.na(Lead_Implementer_Category), "Unknown",
                                            ifelse(Lead_Implementer_Category == "Mixed-Partner", "Mixed-partner", 
                                                   ifelse(Lead_Implementer_Category == "Nonprofit / NGO", "NGO/Nonprofit", Lead_Implementer_Category)))) %>%
  mutate(Lead_Implementer_Category = factor(Lead_Implementer_Category, levels = c("Federal","State","Regional","Local",
                                                                                  "NGO/Nonprofit","Academic","Private",
                                                                                  "Mixed-partner","Other","Unknown")))
  
#### ------- 6. Estuarine Drainage Area  ####

# Remove EDA for brevity
master_db_final <- master_db_final %>%
  mutate(EDA = ifelse(is.na(EDA), NA, str_remove(EDA, " EDA$")))


#### ------- 9. Project Status  ####

# Rename categories
master_db_final <- master_db_final %>%
  mutate(Project_Status = ifelse(is.na(Project_Status), "Unknown", Project_Status)) %>%
  mutate(Project_Status = factor(Project_Status, levels = c("Unknown","Active","Completed")))

  }

# ------------------------------------------------------------------------------
# Review variables and remove those deemed unnecessary for inclusion in the 
# public facing database and reorder variables 
#------------------------------------------------------------------------------

  {
library(dplyr)
library(tidyr)

# Count total number of projects 
total_projects <- n_distinct(master_db_final$Master_Project_ID, na.rm = TRUE)
total_projects

# Replace 0 values with NA for the following columns: 
master_db_final <- master_db_final %>% 
  mutate(
    Project_Acres_Restored = ifelse(Project_Acres_Restored == 0, NA, Project_Acres_Restored),
    Project_Acres_Protected = ifelse(Project_Acres_Protected == 0, NA, Project_Acres_Protected),
    Project_Miles_Restored = ifelse(Project_Miles_Restored == 0, NA, Project_Miles_Restored),
    Project_Miles_Protected = ifelse(Project_Miles_Protected == 0, NA, Project_Miles_Protected),
    Debris_Removed = ifelse(Debris_Removed == 0, NA, Debris_Removed),)

# Calculate the number of unique projects for each variable and the percentage 
# of total projects represented by each variable: 
var_sum <- master_db_final %>%
  summarise(across(
    everything(),
    ~ n_distinct(Master_Project_ID[!is.na(.x)]))) %>%
  pivot_longer(
    everything(),
    names_to = "Variable",
    values_to = "N_Projects") %>%
  mutate(
    Percent_Projects = paste0(
      round(N_Projects / total_projects * 100, 1),"%"))

print(var_sum, n = 100)


# Remove variables that have very limited representation across datasets and are 
# deemed unnecessary to the objectives of the database:
master_db_final <- master_db_final %>% select(-c(Congressional_District,
                                                   Plant_Type, 
                                                   Project_Benefits,
                                                   Permit_Type,
                                                   Agency_Action,
                                                   Permit_ApprovalDate,
                                                   Permit_ExpirationDate,
                                                   Not_HabRest,
                                                   Notes,
                                                   Row))


# Save internal version of the database for internal use and future analysis:
save(master_db_final, file = paste(getwd(),"/Florida Estuarine Restoration Database/master_db_internal.Rdata",sep = ""))

write.csv(master_db_final, file = paste(getwd(),"/Florida Estuarine Restoration Database/master_db_internal.csv",sep = ""), row.names = FALSE)

# Remove variables not necessary for public-facing version of the database:

# NOTE: Following discussion, the working group ultimately decided to exclude
# the variables Funding_Authority and Funding_Authority_Amount from the
# published database because they relied more heavily on expert-driven knowledge
# than on information that could be directly extracted from many of the source
# datasets. We plan to use this information in our separate planned analysis
# manuscript examining restoration trends across the state.

master_db_final <- master_db_final %>% select(-c(Duplicate, 
                                                 Outside_Bounds,
                                                 Cost_per_ton,
                                                 Funding_Authority,
                                                 Funding_Authority_Amount))


colnames(master_db_final)

# Reorder variables for public-facing version of the database:
master_db_final <- master_db_final %>% select("Master_Project_ID", 
                                              "Project_Group_ID",
                                              "Merged_Record_ID", 
                                              "Original_Project_ID",
                                              "Data_Source",
                                              "Data_Source_2",
                                              
                                              "Project_Name",
                                              "Project_Description",
                                              "Project_Status",
                                              
                                              "Start_Year",
                                              "Completion_Year",
                                              "Project_Completion_Year",
                                              "Exp_Completion_Year",
                                              
                                              "County",
                                              "County_Multiple", 
                                              "EDA",
                                              "Latitude",
                                              "Longitude",

                                              "Habitat_Description",
                                              "Project_n_Habitat_Types",
                                              "Habitat_Type",
                                              "Restoration_Technique", 
                                              
                                              "Acres_Restored",
                                              "Acres_Protected",
                                              "Miles_Restored",
                                              "Miles_Protected",
                                              "Project_Acres_Restored", 
                                              "Project_Acres_Protected", 
                                              "Project_Miles_Restored", 
                                              "Project_Miles_Protected", 
                                              "Acres_Restored_Category", 
                                              "Miles_Restored_Category", 
                                              "Project_Acres_Restored_Category",     
                                              "Project_Miles_Restored_Category",

                                              "Debris_Removed", 
                                              "Species_Benefited", 
                                              "Socioeconomic_Jobs_Created", 
                                              "Socioeconomic_Avoided_Travel_Losses", 
                                              "Socioeconomic_Avoided_Damage_Losses", 
                                              "Socioeconomic_Properties_Benefitted", 
                                              
                                              "Main_Funding_Source", 
                                              "Main_Funding_Category",
                                              "Funding_Program", 
                                              "Lead_Implementer",
                                              "Lead_Implementer_Category",
                                              "Partners",
                                              "Reported_Project_Cost",
                                              
                                              "Point_of_Contact_Email",             
                                              "Project_URL",
                                              
                                              "FWC_Grant",
                                              "Federal_Grant", 
                                              "NEP_Name",
                                              "NEP_Activity_Name", 
                                              "Manual_Recode", 
                                              "County_GIS", 
                                              everything())

# Save master_db_final as R.data
save(master_db_final, file = paste(getwd(),"/Florida Estuarine Restoration Database/master_db_final.Rdata",sep = ""))

write.csv(master_db_final, file = paste(getwd(),"/Florida Estuarine Restoration Database/master_db_V1.0.0.csv",sep = ""), row.names = FALSE)

  }
  
}


