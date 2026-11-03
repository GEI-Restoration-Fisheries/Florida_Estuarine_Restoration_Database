# ==============================================================================
# ==============================================================================
# Restoration Database Cleaning Script 
# Updated: HR June 10 2026
# ==============================================================================
# ==============================================================================


# Load necessary libraries -------
library(tidyverse)
library(dplyr)
library(readr)
library(readxl)
library(tibble)
library(purrr)
library(dplyr)
library(stringr)

# Source or load necessary functions ------
{

# Conversion function for D° M.M' to decimal degrees
dms_to_dd <- function(coord_str, is_longitude = FALSE) {
  deg <- as.numeric(str_extract(coord_str, "\\d+(?=°)"))
  min <- as.numeric(str_extract(coord_str, "(?<=° )\\d+\\.?\\d*(?=')"))
  dd <- deg + min / 60
  
  # Apply sign
  if (is_longitude) dd <- -dd   # West is negative
  # North is positive, so no change needed for latitude
  return(dd)
}

# Fix encoding text corruption from excel - csv - R import and export issues: 
fix_encoding <- function(x) {
  # Return non-character columns unchanged
  if (!is.character(x)) return(x)
  
  # Replace common encoding artifacts with the intended characters
  encoding_map <- c(
    "‚Äôs" = "’s",
    "‚Äô"  = "’",
    "‚Äú"  = "“",
    "‚Äù"  = "”",
    "‚Äì"  = "–",
    "‚Äî"  = "—",
    "‚Ä¶"  = "…",
    "‚Ä†"  = "†",
    "‚Ä‡"  = "‡",
    "‚Ä¢"  = "•",
    "‚Äã"  = "",
    "‚Äö√Ñ√¥" = "’",
    "‚Äö√Ñ√¨" = "–",
    "‚Äö√Ñ√®" = "—",
    "‚Äö√Ñ√∂" = "“",
    "‚Äö√Ñ√¶" = "”"
  )
  
  # Apply each replacement
  for (i in seq_along(encoding_map)) {
    x <- gsub(
      names(encoding_map)[i],
      encoding_map[i],
      x,
      fixed = TRUE
    )
  }
  
  x
}

}

# Load data ----------------

# Identify path to folder with raw datasets:
data_path <- file.path(getwd(), "Datasets/Raw")

# Load only .xlsx or xlsm files from that folder that start with "raw_": 
file_list <- list.files(path = data_path, 
                        pattern = "^raw_.*\\.(xlsx|xlsm)$", 
                        full.names = TRUE)

# Import files from file_list: 
for (f in file_list) {
  sheets <- excel_sheets(f)
  
  for (i in seq_along(sheets)) {
    
    base_name <- basename(f) %>%
      str_remove("\\.(xlsx|xlsm)$")  # remvoe extension 
    
    sheet_name <- sheets[i] %>%
      str_replace_all("[[:space:]]+", "_") %>%   # optional: clean spaces
      str_replace_all("[^A-Za-z0-9_]", "")       # optional: remove weird chars
    
    # Only add _SheetX if multiple sheets exist
    newname <- if (length(sheets) > 1) {
      #paste0(base_name, "_Sheet", i)
      paste0(base_name, "_", sheet_name)
    } else {
      base_name
    }
    
    assign(newname, read_excel(f, sheet = i))
  }
}


# Optional: review original datasets & associated variables: 
{
  # Select all 'raw_' datasets and extract column names
  db_list <- mget(ls(pattern = "raw_"))
  col_list <- map(db_list, colnames)
  
  # Find max number of columns and pad with NAs
  max_len <- max(map_int(col_list, length))
  original_variables_df <- map_dfc(col_list, ~ tibble(column = c(., rep(NA, max_len - length(.)))))
  
  # Assign dataset names as column names
  names(original_variables_df) <- names(db_list)
  
  # Print result
  print(original_variables_df)
  
  # Count unique non-NA column names across all datasets
  unique_colnames_count <- original_variables_df %>%
    unlist() %>%
    na.omit() %>%
    unique() %>% # exclude length to see all the variable names 
    length()
  
  # Print the count
  print(paste("Unique number of columns:",unique_colnames_count))
  
  
  # Now count the total number of rows across all the datasets: 
  total_rows <- sum(map_int(db_list, nrow))
  print(paste("Total number of rows:",total_rows))
  
}


# ==============================================================================
# ==============================================================================
# CLEAN AND STANDARDIZE ALL INDIVIDUALL DATASETS 
# ==============================================================================
# ==============================================================================
{
# ------------------------------------------------------------------------------
# NATIONAL ESTUARY PROGRAMC (NEP) DATASETS ----------------------- 
# ------------------------------------------------------------------------------

  {

# NEP 2006-2024 Data --------
clean1a_NEP <- raw_NEP %>% filter(NEP_Name != "Albemarle-Pamlico National Estuary Partnership") %>% # North Carolina NEP projects 
  rename(Original_Project_ID = View_Detail,
         Completion_Year = Federal_Fiscal_Year,
         Legislation_Funding = EPA_Section_320,
         Acres_Restored = Acres,
         Miles_Restored = Miles,
         Feet_Restored = Feet,
         NEP_Activity_Name = Activity_Name) %>%
  select(-c(View_Photos,Map,Region,Author,Submitter_Email,FID,
            NEP_Comments,HQ_Comments,Last_Updated_Date,HQ_Status,Region_Status,
            State_Code,Donated_Land,Data_Unavailable, x,y,Total_Cost)) %>%
  mutate(Data_Source = "NEP",
         Project_Status = "Complete",
         Original_Project_ID = as.character(Original_Project_ID), 
         Total_Project_Cost = as.numeric(Total_Project_Cost), 
         Legislation = if_else(
           !is.na(Legislation_Funding) & Legislation_Funding != "0",
           "Clean Water Act (CWA)",
           NA_character_
         )) %>%
  select(Original_Project_ID, Data_Source, Project_Name, Project_Description, NEP_Activity_Name, Project_Status, Completion_Year, Habitat_Description, Habitat_Type, Restoration_Technique,
         Acres_Restored, Miles_Restored, Feet_Restored, Total_Project_Cost, Main_Funding_Source, Legislation, Legislation_Funding,
         Lead_Implementer, Partners, Latitude,Longitude,NEP_Name)


# NEP 2025 Data --------
clean1b_NEP <- raw_NEP_2025 %>%
  rename(Project_Name = `Project Name`,
         Project_Description = `Project Description`,
         Activity_Name = `Activity Name`,
         Habitat_Description = `Habitat Description`,
         Habitat_Type = `Habitat Type`,
         Restoration_Technique = `Restoration Technique`,
         Total_Project_Cost = `Total Project Cost`,
         Main_Funding_Source = `Main Funding Source`,
         Lead_Implementer = `Lead Implementer`,
         Completion_Year = Year,
         Legislation_Funding = `EPA Section 320`,
         Acres_Restored = Acres,
         Miles_Restored = Miles,
         Feet_Restored = Feet,
         NEP_Activity_Name = `Activity Name`,
         NEP_Name = `NEP Name`) %>%
  select(-c(Region,State,`Donated Land`)) %>%
  mutate(Data_Source = "NEP",
         Project_Status = "Complete",
         Total_Project_Cost = as.numeric(Total_Project_Cost), 
         Legislation = if_else(
           !is.na(Legislation_Funding) & Legislation_Funding != "0",
           "Clean Water Act (CWA)",
           NA_character_
         )) %>% 
  select(Data_Source, Project_Name, Project_Description, Project_Status, NEP_Activity_Name, Completion_Year, Habitat_Description, Habitat_Type, Restoration_Technique,
         Acres_Restored, Miles_Restored, Feet_Restored, Total_Project_Cost, Main_Funding_Source, Legislation, Legislation_Funding,
         Lead_Implementer, Partners, Latitude, Longitude, NEP_Name)


# NEP pre 2006 Data --------
clean1c_NEP <- raw_NEP_pre2006 %>% filter(Federal_Fiscal_Year < 2006) %>%
  select(-Habitat_Type) %>% # blank column for pre 2006 dataset
  rename(Original_Project_ID = ID_Number,
         Completion_Year = Federal_Fiscal_Year,
         Habitat_Type = GeneralHabitat, 
         Acres_Restored = Acres,
         Miles_Restored = Miles,
         Feet_Restored = Feet,
         NEP_Activity_Name = GeneralActivity) %>% 
  mutate(Data_Source = "NEP",
         Project_Status = "Complete",
         Acres_Restored = suppressWarnings(as.numeric(Acres_Restored)),
         Miles_Restored = suppressWarnings(as.numeric(Miles_Restored)),
         Feet_Restored = suppressWarnings(as.numeric(Feet_Restored)),
         Total_Project_Cost = as.numeric(Total_Project_Cost))%>% 
  select(c(Data_Source, Project_Status, Original_Project_ID, Project_Name, Project_Description, Completion_Year, Restoration_Technique, Total_Project_Cost,
           Project_Benefits,Lead_Implementer, Partners, Latitude, Longitude, NEP_Activity_Name, 
           Acres_Restored, Miles_Restored, Feet_Restored, Habitat_Type,NEP_Name)) 
clean1c_NEP$Total_Project_Cost <- as.numeric(clean1c_NEP$Total_Project_Cost)


# Merge db1a_clean and db1b_clean: 
clean_NEP <- bind_rows(clean1a_NEP, clean1b_NEP, clean1c_NEP)

# Add point of contact for projects:
clean_NEP <- clean_NEP %>%
  mutate(
    Point_of_Contact_Email = case_when(
      NEP_Name == "Coastal and Heartland National Estuary Partnership" ~ "chnep@chnep.org",
      NEP_Name == "Tampa Bay Estuary Program" ~ "info@tbep.org",
      NEP_Name == "Sarasota Bay Estuary Program" ~ "info@sarasotabay.org",
      NEP_Name == "Indian River Lagoon NEP" ~ "info@irlcouncil.org",
      TRUE ~ NA_character_ ))

# If the main funding source is ARPA or American Rescue Fund: assume the project 
# is 100% legislation federally funded, set Legislation_Funding = Total_Project_Cost, 
# and label the Legislation field accordingly: 
clean_NEP <- clean_NEP %>%
  mutate(
    Legislation_Funding = case_when(
      Main_Funding_Source %in% c(
        "American Rescue Plan Act (ARPA)",
        "American Rescue Fund") ~ Total_Project_Cost,
      TRUE ~ Legislation_Funding),
    Legislation = case_when(
      Main_Funding_Source == "American Rescue Plan Act (ARPA)" ~ "American Rescue Plan Act (ARPA)",
      Main_Funding_Source == "American Rescue Fund" ~ "American Rescue Plan Act (ARPA)",
      TRUE ~ Legislation))



# Supplemental update: update the categories of Habitat_Type and Restoration_Technique
# for select projects that were originally categorized as 'other', general categories,
# or did not have values for these variables. The updated categories are based on 
# the project descriptions and other information provided by the NEP (see protocol for details). 

#install.packages("googlesheets4")
library(googlesheets4)

# make sure general access is set to anyone with link can view
# gs4_deauth()   # clears any existing token
# gs4_auth()     # prompts you to sign in again

# IF anyone needs re-authorization: 
#gs4_auth(scopes = "https://www.googleapis.com/auth/spreadsheets.readonly")

NEP_supplemental <- read_sheet("https://docs.google.com/spreadsheets/d/1S8U7YAI6n99iNR-nxUll9lbJLyz261ghDCYtoWXdI3s/edit?usp=sharing", sheet = "updated_categories") 
NEP_supplemental <- NEP_supplemental %>% mutate(Original_Project_ID = as.character(Original_Project_ID))

# Incorporate the supplemental updates into the clean_NEP dataset:
# If Original_Project_ID matches the Original_Project_ID in the supplemental
# dataset, update the Habitat_Type and Restoration_Technique values in clean_NEP
# with the values from the Standardized_Restoration_Technique and 
# Standardized_Habitat_Type and supplemental dataset.
clean_NEP <- clean_NEP %>%
  left_join(NEP_supplemental %>% select(Original_Project_ID, Standardized_Habitat_Type, Standardized_Restoration_Technique), by = "Original_Project_ID") %>%
  mutate(
    Manual_Recode = if_else(!is.na(Standardized_Habitat_Type) | !is.na(Standardized_Restoration_Technique),1,0), # flag for projects that were updated based on the supplemental dataset
    Habitat_Type = if_else(!is.na(Standardized_Habitat_Type), Standardized_Habitat_Type, Habitat_Type),
    Restoration_Technique = if_else(!is.na(Standardized_Restoration_Technique), Standardized_Restoration_Technique, Restoration_Technique)) %>%
  select(-Standardized_Habitat_Type, -Standardized_Restoration_Technique)

# Incorporate the subset of NEP_supplemental projects that don't have Original_Project_ID values (NA): 
NEP_supplemental_no_ID <- NEP_supplemental %>% filter(Original_Project_ID == "NA")

clean_NEP <- clean_NEP %>%
  left_join(NEP_supplemental_no_ID %>% select(Project_Name, Standardized_Habitat_Type, Standardized_Restoration_Technique), by = "Project_Name") %>%
  mutate(
    Manual_Recode = pmax(Manual_Recode,if_else(!is.na(Standardized_Habitat_Type) | !is.na(Standardized_Restoration_Technique), 1, 0)), # flag for projects that were updated based on the supplemental dataset
    Habitat_Type = if_else(!is.na(Standardized_Habitat_Type), Standardized_Habitat_Type, Habitat_Type),
    Restoration_Technique = if_else(!is.na(Standardized_Restoration_Technique), Standardized_Restoration_Technique, Restoration_Technique)) %>%
  select(-Standardized_Habitat_Type, -Standardized_Restoration_Technique)


# remove no longer necessary dataframes free up memory:
rm(clean1a_NEP,clean1b_NEP,clean1c_NEP,NEP_supplemental,NEP_supplemental_no_ID)


# Save the cleaned NEP dataset to a CSV file for future use:
write_excel_csv(clean_NEP, paste(getwd(),"/Datasets/Cleaned/clean_NEP.csv", sep = ""))

# General notes:
# NEP: Completion_Year = Federal_Fiscal_Year 
# NEP: Activity_Name = options of Restoration, Maintenance, Monitoring 
# NEP: EPA_Section_320 = represents funding from Clean Water Act (accounted for in the total project cost column )
}

# ------------------------------------------------------------------------------
# NOAA RESTORATION DATASET -------------------------------------------
# ------------------------------------------------------------------------------

  {

# Merge the two NOAA sheets together before standardization and cleaning. 
# Given the NOAA spreadsheet structure, all project-level metadata stays 
# the same and only the habitat-related columns vary across rows (each  project 
# in Sheet 1:FL_Projects_w_Added_Financials gets repeated for each matching 
# habitat row in Sheet 2:FL_Accomplishments_Portal)


# Calculate the most recent fiscal year for each project (regardless of habitat 
# type) and then combine acreage for given project x habitat type, so
# results in single row per project number x habitat type with the most recent 
# fiscal year date for the given project: 
NOAA_hab <- raw_NOAA_FL_Accomplishments_Portal %>%
  group_by(`Project Number`) %>%
  mutate(`Fiscal Year` = if (all(is.na(`Fiscal Year`))) {NA_real_} 
          else {max(`Fiscal Year`, na.rm = TRUE)}) %>% # keep most recent year
  ungroup() %>%
  select(`Project Number`, 
         `Project Status`,
         `Fiscal Year`,
          Habitat,
         `Actual Acres Restored`,
         `Actual Acres Protected`,
         `Actual Stream Miles Opened`) %>%
  group_by(`Project Number`, `Project Status`,`Fiscal Year`, Habitat) %>%
  summarise(
    `Actual Acres Restored` = sum(`Actual Acres Restored`, na.rm = TRUE),
    `Actual Acres Protected` = sum(`Actual Acres Protected`, na.rm = TRUE),
    `Actual Stream Miles Opened` = sum(`Actual Stream Miles Opened`, na.rm = TRUE),
    .groups = "drop")


# Merge the habitat data with the project-level metadata to create multiple 
# rows per project number for projects that have multiple habitat types: 
clean_NOAA <- raw_NOAA_FL_Projects_w_Added_Financials_ %>%
  left_join(NOAA_hab, by = "Project Number") 


# Quality control check: Differences are identified because the raw_NOAA_Sheet1
# includes projects that are education focused and therefore have no habitat 
# rows in raw_NOAA_Sheet2, which explains why merging the sheets creates more 
# rows than in the habitat sheet alone (raw_NOAA_Sheet2). 
{
# Count rows per project in each dataset
hab_counts <- NOAA_hab %>%
  count(`Project Number`, name = "n_hab")

clean_counts <- clean_NOAA %>%
  count(`Project Number`, name = "n_clean")

# Join them side by side
comparison <- full_join(hab_counts, clean_counts, by = "Project Number") %>%
  arrange(desc(n_clean))

rm(clean_counts, hab_counts, comparison)
}

# NOAA Data -----------
clean_NOAA <- clean_NOAA %>%   
  filter(
      # Remove projects outside spatial scope
      !`Project Number` %in% c("5622") & 
      # Remove projects focused on program / operations development or research: 
      !`Project Number` %in% c("1123","1124","1131","1132","2733","5465","5714","5791","1319","1330","1332","1437","1440","1753","1755","1759","1982","1985","2344","423","447","472","473","767","1096","1102","1216","474","912") &
      # Remove projects focused on debris removal only 
      !`Project Number` %in% c("4247","2111")) %>%
  rename(Original_Project_ID = `Project Number`,
         Project_Name = `Project Name`,
         Project_Status = `Project Status.y`, # this is more accurate (from accomplishments sheet) 
         #Project_Status = `Project Status`,
         Project_Description = Description,
         Funding_Program = Program,
         Start_Year = `Construction Start Date`,
         Completion_Year = `Fiscal Year`,
         Lead_Implementer = `Funding Recipients`,
         Restoration_Technique = `Techniques`, 
         Habitat_Type = `Habitat`,
         Acres_Restored = `Actual Acres Restored`, # not sheet 1 'Actual Acres Restored includes mods'
         Acres_Protected = `Actual Acres Protected`,
         Miles_Restored = `Actual Stream Miles Opened`,
         Debris_Removed = `Debris Removed (tons)`,
         Species_Benefited = `Species Benefited`) %>%
  dplyr::select(-State,`Has Listed Species?`,`Primary Strategy`,`Project Status.x`) %>% 
  mutate(Data_Source = "NOAA",
         Main_Funding_Source = "NOAA",
         Total_Project_Cost = `NOAA Contributions (project total)` + `Sum of Other Contributions`,
         Start_Year = gsub("[\"`]", "", Start_Year),
         Start_Year = as.Date(Start_Year),
         Start_Year = as.numeric(format(Start_Year, "%Y"))) %>%
  rename(Legislation_Funding = `NOAA Contributions (project total)`) %>%
  dplyr::select(Original_Project_ID, Data_Source, Project_Name, Project_Description, Project_Status, 
         Start_Year, Completion_Year, Habitat_Type,Restoration_Technique, Acres_Restored, Debris_Removed, 
         Acres_Protected, Miles_Restored, Main_Funding_Source, Funding_Program, Legislation_Funding, 
         Total_Project_Cost,Lead_Implementer,Species_Benefited, Latitude, Longitude) 

# Separate out the legislation and the NOAA programs into appropriate variables:
clean_NOAA <- clean_NOAA %>% mutate(
  Legislation = if_else(Funding_Program %in% c("ARRA of 2009", "DARRP","RESTORE Act","IIJA of 2021"),
                        Funding_Program,
                        NA_character_),
  Funding_Program = if_else(Funding_Program %in% c("ARRA of 2009", "DARRP","RESTORE Act","IIJA of 2021"),
                            NA_character_,
                            Funding_Program))

# Add 'NOAA' in front of the current funding programs not associated with legislation:
clean_NOAA <- clean_NOAA %>% mutate(
  Funding_Program = case_when(!is.na(Funding_Program) ~
                            paste("NOAA", Funding_Program),
                            TRUE ~ Funding_Program))

# Add more detail to the RESTORE Act funded projects: 
clean_NOAA <- clean_NOAA %>% mutate(
    Funding_Program = case_when(Legislation == "RESTORE Act" ~
        "The RESTORE Act Funds Bucket 2: Comprehensive Plan",
         TRUE ~ Funding_Program))

# Set all projects with no associated Legislation to have Legislation_Funding = 0:
clean_NOAA <- clean_NOAA %>% mutate(
  Legislation_Funding = case_when(is.na(Legislation) ~ 0,
                              TRUE ~ Legislation_Funding))


# Assign random Project_Group_ID values to projects that have the same duplicate
# Original_Project_ID only: 
clean_NOAA <- clean_NOAA %>%
  mutate(Project_Group_ID = ifelse(
    Original_Project_ID %in% names(which(table(Original_Project_ID) > 1)),
    700 + match(Original_Project_ID, names(which(table(Original_Project_ID) > 1))), NA))

# Add point of contact for projects:
clean_NOAA <- clean_NOAA %>%
  mutate(Point_of_Contact_Email = "restoration.atlas@noaa.gov")    


# Review dataset to determine if there are any projects that do not incorporate
# habitat restoration.
  # Upon review, all projects that include 'invasives removal: fauna' also 
  # include habitat restoration, so no projects should be excluded.  
  # note: projects focusing exclusively on debris removal were already excluded
  # in code above. 
  # Therefore,  all projects that remain in the dataset have some habitat 
  # restoration component, so no further filtering is needed. 

rm(NOAA_hab)

# Save the cleaned dataset to a CSV file for future use:
write_excel_csv(clean_NOAA, paste(getwd(),"/Datasets/Cleaned/clean_NOAA.csv", sep = ""))


# General notes: 
# NOAA: Actual acres restored and protected both include mods (modifications)
# NOAA: Funding Recipients = Lead Implementer 

}

# ------------------------------------------------------------------------------
# SNAPP DATASET -------------------------
# ------------------------------------------------------------------------------

  {
clean_SNAPP <- raw_SNAPP %>%
  rename(Original_Project_ID = `Master_Project_ID`,
         Start_Year = `Award_Years`,
         Completion_Year = `Completion_Year`,
         Habitat_Type = `Restoration_Habitat`,
         Acres_Restored = `Actual_Area_Restored_acres`,
         Miles_Restored = `Actual_Stream_Opened_miles`) %>%
  select(-c(Region,State,CountyState,FID,x,y))  %>%
  mutate(Data_Source = "SNAPP",
         Completion_Year = ifelse(Completion_Year %in% c("NA", "", "unknown"), NA, Completion_Year),
         Completion_Year = as.numeric(Completion_Year),
         Acres_Restored = ifelse(Acres_Restored %in% c("NA", "", "unknown"), NA, Acres_Restored),
         Acres_Restored = as.numeric(Acres_Restored),
         Miles_Restored = ifelse(Miles_Restored %in% c("NA", "", "unknown"), NA, Miles_Restored),
         Miles_Restored = as.numeric(Miles_Restored),
         Latitude = as.numeric(Latitude),
         Longitude = as.numeric(Longitude)
  ) %>%
  select(Original_Project_ID, Data_Source, Project_Name, Project_Description, Project_Status,
         Start_Year, Completion_Year, Habitat_Type, Acres_Restored, Miles_Restored,
         County,Latitude, Longitude)

# Save the cleaned dataset to a CSV file for future use:
write_excel_csv(clean_SNAPP, paste(getwd(),"/Datasets/Cleaned/clean_SNAPP.csv", sep = ""))


# General notes:
# SNAPP: No Restoration Technique - but could maybe pull this from the Project_Description
}

# ------------------------------------------------------------------------------
# DIVER DATASET ------------------------------------
# ------------------------------------------------------------------------------

  {
  
# DIVER data --------
clean_DIVER <- raw_DIVER %>% filter(!Project_Status %in% c("Terminated")) %>%
  filter(Record_Type == "Project" & 
         # Remove all projects focused only on storm water treatment / sewage
         !Project_ID %in% c("199","200","368","370","373","375","377","378") &
         # Remove all projects that identify 'project and planning' in the title 
         !Project_ID %in% c("179","197","200","201","202") &
         # Remove all scientific study projects  
         !Project_ID %in% c("288")) %>% 
  rename(County = `County__All_`,
         Project_Description = `Project_Overview_Site_Description`,
         Primary_Strategy = `Project_Restoration_Type`,
         Latitude = `Start_Latitude`,
         Longitude = `Start_Longitude`) %>%
  select(-c("_",Case_Activity, FID,Project_Overview_Site_Name, Data_Category, 
            Project_Overview_Location_Geom,Trustee_Implementation_Group, 
            DIVER_Dataset,Record_Type,x,y,`Location__All_`)) %>%
  mutate(Data_Source = "DIVER",
         Main_Funding_Source = "Florida Trustee Implimentation Group",
         Original_Project_ID = as.character(Project_ID)) %>%
  select(Original_Project_ID,Data_Source, Project_Name, Project_Description, Project_Status,
         Primary_Strategy,  Main_Funding_Source, County,
         Latitude, Longitude,Project_URL)


# General notes:
# DIVER: REMOVED all samples where Record_Type = Planning (as opposed to project), 
#        because these are the general FL TIG Restoration Plans #1, #2, #3 etc 
#        that are general summaries of the remaining restoration project inputs,
#        therefore also removed the X samples as well as the Record_Type column 


# Dataset was now exported, and we requested the project level metadata
# in house from NOAA DIVER data manager, updated the dataset metadata 
# (DIVER folder) and re-uploaded the new DIVER file: 

# Upload new DIVER processed file here and replace the original raw data: 
clean_DIVER <- read_excel(paste(getwd(),"/Datasets/Supporting Documents/DIVER/DIVER_processed.xlsx", sep = "")) 

# Clean formatting from upload: 
clean_DIVER <- clean_DIVER %>%
  mutate(across(where(is.character), 
                ~ na_if(na_if(na_if(., "NA"), "N/A"), ""))) %>% # Remove all NA's 
  select(-c(`component id`,Primary_Strategy)) 

# Fix date formatting: 
clean_DIVER$Completion_Year <- as.Date(as.numeric(clean_DIVER$Completion_Year),
                                                  origin = "1899-12-30")

# Correct encoding issues with fix_encoding function: 
clean_DIVER <- clean_DIVER %>% mutate(across(where(is.character), fix_encoding))

# Select only the year from the date:
clean_DIVER <- clean_DIVER %>%
  mutate(Completion_Year = as.numeric(format(Completion_Year, "%Y")))

# Remove Stream_Opened: 
clean_DIVER <- clean_DIVER %>% select(-Stream_Opened)

# Add Legislation: 
clean_DIVER <- clean_DIVER %>% mutate(Legislation = "OPA of 1990") 

# Save the cleaned dataset to a CSV file for future use:
write_excel_csv(clean_DIVER, paste(getwd(),"/Datasets/Cleaned/clean_DIVER.csv", sep = ""))

}

# ------------------------------------------------------------------------------
# FWC ARTIFICIAL REEFS DATASET ----------------------------
# ------------------------------------------------------------------------------

  {

# Input dataset from artificial reefs here 
clean_FWC_REEFS <- raw_FWC_REEFS_Estuarine_DeployCostCLEAN  %>% 
  rename(Original_Project_ID = `DeployID`,
         Project_Name = `Deployment Name`,
         Project_Description = Description,
         Latitude = `Latitude DD`,
         Longitude = `Longitude DD`,
         SqFt_Restored = Area, 
         Total_Project_Cost = `Total Funding (byDeployID)`,
         Main_Funding_Source = `Funding Source - Entity`,
         Funding_Program = `Funding Source - Fund`,
         FWC_Grant = `FWC Grant`,
         Federal_Grant = `Federal Grant`,
         Cost_per_ton = `Cost per ton`) %>%
  mutate(
    Completion_Year = as.numeric(substr(DeployDate, 1, 4)),
    SqFt_Restored = as.numeric(na_if(SqFt_Restored, "UNK")),
    Acres_Restored = SqFt_Restored / 43560,
    Data_Source = "FWC_REEFS",
    Habitat_Type = "hard bottom",
    Restoration_Technique = "reef construction",
    Project_Status = "Completed",
    Lead_Implementer = "FWC")  %>%
  select(Data_Source,Original_Project_ID,Project_Name,Project_Description,Project_Status, 
         County,Habitat_Type, Restoration_Technique, Completion_Year, Latitude,
         Longitude, Acres_Restored, Main_Funding_Source, Lead_Implementer, 
         Funding_Program, Total_Project_Cost, FWC_Grant, Federal_Grant, Cost_per_ton)

# Add point of contact for projects:
clean_FWC_REEFS <- clean_FWC_REEFS %>%
  mutate(Point_of_Contact_Email = "ArtificialReefDeployments@MyFWC.com") 

# Save the cleaned dataset to a CSV file for future use:
write_excel_csv(clean_FWC_REEFS, paste(getwd(),"/Datasets/Cleaned/clean_FWC_REEFS.csv", sep = ""))


}

# ------------------------------------------------------------------------------
# FDEP DATASET ------------------------------------
# ------------------------------------------------------------------------------
  
  {
    
# FDEP data -------
clean_FDEP <- raw_FDEP %>% filter(!`Agency Action` %in% c("Withdrawn", "Denied", "Pending")) %>%
  rename(Original_Project_ID = `Application #`,
         Project_Name = `Project Name`,
         Project_Description = `Fac/Site Name`,
         Permit_Type = `Permit Type / Subtype`,
         Permit_ApprovalDate = `Agency Action Date`,
         Permit_ExpirationDate = `Expiration Date`,
         Agency_Action = `Agency Action`) %>%
  select(-c(Program,Office,`State Land Code`,Received,`Application Action`,ObjectId,x,y)) %>%
  mutate(Data_Source = "FDEP",
         Permit_ApprovalDate = gsub("[\"`]", "", Permit_ApprovalDate),           
         Permit_ApprovalDate = as.Date(Permit_ApprovalDate, format = "%Y-%m-%d"),
         Permit_ApprovalDate = as.numeric(format(Permit_ApprovalDate, "%Y")),
         Permit_ExpirationDate = gsub("[\"`]", "", Permit_ExpirationDate),           
         Permit_ExpirationDate = as.Date(Permit_ExpirationDate, format = "%Y-%m-%d"),
         Permit_ExpirationDate = as.numeric(format(Permit_ExpirationDate, "%Y")))  %>%
  select(c(Original_Project_ID,Data_Source,Project_Name,Project_Description, Permit_Type,
           Permit_ApprovalDate,Agency_Action,Permit_ExpirationDate,County,Latitude,Longitude))

# Save the cleaned dataset to a CSV file for future use:
write_excel_csv(clean_FDEP, paste(getwd(),"/Datasets/Cleaned/clean_FDEP.csv", sep = ""))


# NOTE on Florida DEP Permits
# Removed all agency actions that were denied or withdrawn  (kept issued effective pending)
# All data is from the Environmental Resource Permitting (ERP) program
# Removed the Application submission date, but kept approval and expiration date 

  }
  
# ------------------------------------------------------------------------------
# NFWF: NCRF and ECRF DATASETS ----------------------------
# ------------------------------------------------------------------------------
  
  {
    
# NFWF NCRF and ECRF data ----------
clean_NFWF_NCRFandECRF <- raw_NFWF_NCRFandECRF %>% filter(`grant_type` %in% c("Implementation")) %>% 
  rename(Original_Project_ID = ez_grant_id,
         Project_Name = grant_title,
         Project_Status = project_status,
         Start_Year = year_awarded, 
         Habitat_Type = sub_category,
         Restoration_Technique = nature_based_solution,
         Funding_Program = program,
         Lead_Implementer = grantee,
         Congressional_District = congressional_district) %>%
  select(-c(grantee_type, grant_type, grants_directly_engaging_communities, project_site,region,state)) %>%
  pivot_wider(names_from = measure,
              values_from = metric_value)  %>%
  rename(Acres_Restored = `Acres Restored`,
         Miles_Restored = `Miles Restored & Created`,
         Socioeconomic_Jobs_Created = `Jobs Created`,
         Socioeconomic_Properties_Benefitted = `Total # of Properties Benefitted from Enhanced Protection`,
         Socioeconomic_Avoided_Damage_Losses = `Avoided Property Damage & Reduced Repairs (Millions $)`,
         Socioeconomic_Avoided_Travel_Losses = `Avoided Travel Time Losses (Thousands $)`) %>%
  select(-c(`Barriers Removed`)) %>%
  mutate(Data_Source = "NFWF_NCRFandECRF",
         Main_Funding_Source = "NFWF")

# Manually remove projects that upon review fall outside spatial scope:  
# (e.g., 2x FL Keys outer shores, and project that is the planning of a 
# duplication of other implementation project (76084)): 
clean_NFWF_NCRFandECRF <- clean_NFWF_NCRFandECRF %>% filter(!Original_Project_ID %in% c("69525","62145","69239"))

# Summarize the metrics across the socioeconomic projects:  
clean_NFWF_NCRFandECRF <- clean_NFWF_NCRFandECRF %>%
  group_by(Original_Project_ID, class) %>%
  mutate(
        Habitat_Type = ifelse(class == "Socioeconomic", NA, Habitat_Type),
        across(
          starts_with("Socioeconomic_"),
          function(x) if (class[1] == "Socioeconomic") sum(x, na.rm = TRUE) else x)) %>%
  ungroup() %>%
  distinct()

# For each Unique_Project_ID, select the Socioeconomic metrics and copy them over
# into all rows where class == "Ecological" for that same project: 

# Extract one socioeconomic row per project
socio_metrics <- clean_NFWF_NCRFandECRF %>%
  filter(class == "Socioeconomic") %>%
  select(Original_Project_ID,
         Socioeconomic_Avoided_Travel_Losses,
         Socioeconomic_Avoided_Damage_Losses,
         Socioeconomic_Jobs_Created,
         Socioeconomic_Properties_Benefitted)

# Join the socioeconomic metrics into the Ecological rows
clean_NFWF_NCRFandECRF <- clean_NFWF_NCRFandECRF %>%
  left_join(socio_metrics,
            by = "Original_Project_ID",
            suffix = c("", "_socio")) %>%
  mutate(
    Socioeconomic_Avoided_Travel_Losses =
      ifelse(class == "Ecological",
             Socioeconomic_Avoided_Travel_Losses_socio,
             Socioeconomic_Avoided_Travel_Losses),
    Socioeconomic_Avoided_Damage_Losses =
      ifelse(class == "Ecological",
             Socioeconomic_Avoided_Damage_Losses_socio,
             Socioeconomic_Avoided_Damage_Losses),
    Socioeconomic_Jobs_Created =
      ifelse(class == "Ecological",
             Socioeconomic_Jobs_Created_socio,
             Socioeconomic_Jobs_Created),
    Socioeconomic_Properties_Benefitted =
      ifelse(class == "Ecological",
             Socioeconomic_Properties_Benefitted_socio,
             Socioeconomic_Properties_Benefitted)) %>% 
  select(-ends_with("_socio")) %>% filter(class != "Socioeconomic")


# NOTES on the NFWF_NCRFandECRF: 
# Lat/long are not provided, nor completion date 
# Only implemented projects were included (not planning or design phases)


# At this point we exported this dataset out, and supplemented metadata blank
# values with funding information from NFWF reports / documents etc, and then 
# re-uploaded with new data.

# Export dataset: 
write_excel_csv(clean_NFWF_NCRFandECRF, paste0(getwd(),"/Datasets/Supporting Documents/NFWF_NCRFandECRF/NFWF_NCRFandECRF_preprocessed.csv"))

# Import updated dataset: 
clean_NFWF_NCRFandECRF <- read_excel(paste0(getwd(),"/Datasets/Supporting Documents/NFWF_NCRFandECRF/NFWF_NCRFandECRF_processed.xlsx")) 

# Remove the NA characters from the upload: 
clean_NFWF_NCRFandECRF <- clean_NFWF_NCRFandECRF %>% 
  mutate(across(where(is.character),
                ~ na_if(na_if(na_if(., "NA"), "N/A"), "")),
         Miles_Restored = as.numeric(Miles_Restored))

# Assign random Project_Group_ID values to projects that have the same duplicate
# Original_Project_ID only: 
clean_NFWF_NCRFandECRF <- clean_NFWF_NCRFandECRF %>% 
  group_by(Original_Project_ID) %>%
  mutate(Project_Group_ID = ifelse(n() > 1,  # only if duplicated, 
                                   first(400 + cur_group_id() - 1), # assign randomly in the 400s
                                   NA)) 

# Add point of contact for projects:
clean_NFWF_NCRFandECRF <- clean_NFWF_NCRFandECRF %>%
  mutate(Point_of_Contact_Email = "info@nfwf.org")    

rm(socio_metrics)

# Add additional requested information (spatial) from direct request to NFWF:
library(sf)
NFWF_NCRFandECRF_spatial_supplemental <- st_read(paste(getwd(),
 "/Datasets/Supporting Documents/NFWF_NCRFandECRF/20260811_NCRF_ECRF/20260811_NCRF_ECRF.shp", sep = ""))  

# Convert spatial points from Web Mercator to longitude/latitude
spatial_coords <- NFWF_NCRFandECRF_spatial_supplemental %>%
  st_transform(4326) %>%
  mutate(
    Longitude = st_coordinates(.)[, 1],
    Latitude = st_coordinates(.)[, 2]) %>%
  st_drop_geometry() %>%
  select(EZG_ID, Longitude, Latitude)

# Add coordinates to the dataset
clean_NFWF_NCRFandECRF <- clean_NFWF_NCRFandECRF %>%
  left_join(
    spatial_coords,
    by = c("Original_Project_ID" = "EZG_ID"))

# Save the cleaned dataset to a CSV file for future use:
write_excel_csv(clean_NFWF_NCRFandECRF, paste(getwd(),"/Datasets/Cleaned/clean_NFWF_NCRFandECRF.csv", sep = ""))


}

# ------------------------------------------------------------------------------
# NFWF: GEBF DATASET ----------------------------
# ------------------------------------------------------------------------------
  
  {
# NFWF GEBF data ------
clean_NFWF_GEBF <- raw_NFWF_GEBF %>% 
  mutate(Start_Year = as.numeric(substr(Start_Year, 1, 4)),
         Completion_Year = as.numeric(substr(Completion_Year, 1, 4)),
         Data_Source = "NFWF_GEBF")

# Add Legislation text to all projects (same terminology as DWH): 
clean_NFWF_GEBF <- clean_NFWF_GEBF %>% 
  mutate(Legislation = "Guilty Plea Agreement between BP and U.S. Department of 
         Justice, Guilty Plea Agreement between Transocean and U.S. Department 
         of Justice")

# Add point of contact for projects:
clean_NFWF_GEBF <- clean_NFWF_GEBF %>%
  mutate(Point_of_Contact_Email = "info@nfwf.org")    

# Assign random Project_Group_ID values to projects that have the same duplicate
# Project Name only: 
clean_NFWF_GEBF <- clean_NFWF_GEBF %>%
  group_by(Project_Name) %>%
  mutate(Project_Group_ID = ifelse(
      n() > 1,  # only if duplicated
      first(500 + cur_group_id() - 1),NA)) %>% # random value in the 500s
  ungroup()

# Add additional requested information from direct request to NFWF: 
NFWF_GEBF_supplemental <- read_excel(paste0(getwd(),
                          "/Datasets/Supporting Documents/NFWF_GEBF/NFWF_GEBF_supplemental.xlsx"))

# If Project_Name matches, update the Project_Status, Start_Year, and Completion_Year: 
clean_NFWF_GEBF <- clean_NFWF_GEBF %>%
  left_join(
    NFWF_GEBF_supplemental %>% 
      mutate(Completion_Year = as.numeric(format(Completion_Year, "%Y"))) %>% 
      select(Project_Name, Project_Status, Start_Year, Completion_Year),
    by = "Project_Name",
    suffix = c("", ".supp")) %>%
  mutate(
    Project_Status = coalesce(Project_Status.supp, Project_Status),
    Start_Year = coalesce(Start_Year.supp, Start_Year),
    Completion_Year = coalesce(Completion_Year.supp, Completion_Year)) %>%
  select(-ends_with(".supp"))

# If Completion_Year >2025, move that value to the new column
# 'Exp_Completion_Year' and set Completion_Year to NA:
clean_NFWF_GEBF <- clean_NFWF_GEBF %>%
  mutate(
    Exp_Completion_Year = ifelse(Completion_Year > 2025, Completion_Year, NA),
    Completion_Year = ifelse(Completion_Year > 2025, NA, Completion_Year))

# Add additional requested information (spatial) from direct request to NFWF:
library(sf)
NFWF_GEBF_spatial_supplemental <- st_read(paste(getwd(),
                                  "/Datasets/Supporting Documents/NFWF_GEBF/20260811_GEBF/20260811_GEBF.shp", sep = ""))  


# Convert spatial points from Web Mercator to longitude/latitude
spatial_coords <- NFWF_GEBF_spatial_supplemental %>%
  st_transform(4326) %>%
  mutate(
    Longitude = st_coordinates(.)[, 1],
    Latitude = st_coordinates(.)[, 2]) %>%
  st_drop_geometry() %>%
  select(EZG_ID, Longitude, Latitude)

# Add additional information requested from NFWF to link the spatial data to the
# main dataset through the original project ID (EZG_ID) and the Project_Name:
clean_NFWF_GEBF <- clean_NFWF_GEBF %>% mutate(Original_Project_ID = case_when(
      Project_Name == "Restoration and Management of Escribano Point Coastal Habitat - Phase I" ~ 40620, 
      Project_Name == "Restoration and Management of Escribano Point Coastal Habitat - Phase II" ~ 44562, 
      Project_Name == "Pensacola East Bay Oyster Habitat Restoration - Phase II" ~ 61601, 
      Project_Name == "Restoration of Florida’s Coastal Dune Lakes - Phase I" ~ 46147, 
      Project_Name == "Restoration of Florida’s Coastal Dune Lakes - Phase II" ~ 48340, 
      Project_Name == "Pensacola Bay Living Shoreline Project - White Island Habitat Restoration" ~ 70175, 
      Project_Name == "Apalachicola Bay Oyster Restoration - Phase I" ~ 40623, 
      Project_Name == "Apalachicola Bay Oyster Reef Restoration - Phase II" ~ 65905, 
      TRUE ~ NA_real_)) %>%
  relocate(Original_Project_ID, .before = Project_Name)

# Add coordinates to the dataset
clean_NFWF_GEBF <- clean_NFWF_GEBF %>%
  left_join(spatial_coords, by = c("Original_Project_ID" = "EZG_ID"))

# Save the cleaned dataset to a CSV file for future use:
write_excel_csv(clean_NFWF_GEBF, paste(getwd(),"/Datasets/Cleaned/clean_NFWF_GEBF.csv", sep = ""))

}

# ------------------------------------------------------------------------------
# FWC MESS DATASET ----------------------------
# ------------------------------------------------------------------------------
  
  {
clean_FWC_MESS <- raw_FWC_MESS %>% 
  mutate(Original_Project_ID = Data_Source,
         Project_Status = ifelse(!is.na(Completion_Year), "Complete", NA),
         Data_Source = "FWC_MESS")

# Assign Project_Group_ID values to projects that have the same duplicate
# Original_Project_ID only: 
clean_FWC_MESS <- clean_FWC_MESS %>% 
  group_by(Original_Project_ID) %>%
  mutate(Project_Group_ID = ifelse(
    n() > 1,  # only if duplicated, 
    first(600 + cur_group_id() - 1), NA))  %>% # random value in the 600s
  ungroup()

# Add point of contact for projects:
clean_FWC_MESS <- clean_FWC_MESS %>%
  mutate(Point_of_Contact_Email = "AquaticHabitat@myfwc.com")    

# Save the cleaned dataset to a CSV file for future use:
write_excel_csv(clean_FWC_MESS, paste(getwd(),"/Datasets/Cleaned/clean_FWC_MESS.csv", sep = ""))

  
}

# ------------------------------------------------------------------------------
# NACC DATASET ----------------------------
# ------------------------------------------------------------------------------
  
  {
# NACC data ------
clean_NACC <- raw_NACC %>% filter(Removed =="yes") %>% 
  rename(Original_Project_ID = SARPID,
         Project_Name = Name,
         Completion_Year = YearRemoved,
         Latitude = lat,
         Longitude= lon,
         Acres_Restored = WaterbodyAcres,
         Project_URL = URL) %>% 
  mutate(
    Project_Name = ifelse(!is.na(River), paste(Project_Name, River, sep = ", "), Project_Name), # Merge the values from Project_Name and River into Project_Name for more description 
    Completion_Year = ifelse(Completion_Year == 0, NA, Completion_Year), # Replace 0 values with NA in column Completion_Year
    Project_Status = ifelse(!is.na(Completion_Year), "Completed", NA), # Add Project_Status column based on Completion_Year
    Acres_Restored = ifelse(Acres_Restored == -1, NA, Acres_Restored), # Replace -1 with NA for no associated waterbody
    Habitat_Type = "tidal tributary/creek/river", # manually add in habitat type (all projects occurs in creeks)
    Restoration_Technique = "hydrologic restoration", # manually add in restoration technique (all projects are dam removal) 
    Data_Source = "NACC") %>% 
  select(Data_Source,Original_Project_ID,Project_Name,Completion_Year,Habitat_Type,Restoration_Technique,Acres_Restored,Latitude,Longitude,Project_URL)

# Source metadata: 
# lat: Latitude in WGS84 geographic coordinates. 
# lon: Longitude in WGS84 geographic coordinates. 
# Name: dam or surveyed road/stream crossing name, if available. 
# SARPID: SARP Identifier. Removed: Identifies if the dam or surveyed
# road/stream crossing has been removed for conservation, if known.  Removed
# barriers will not have values present for all fields. 
# YearRemoved: year that barrier was removed or mitigated, if available.  All 
# barriers removed prior to 2000 or where YearRemoved is unknown were lumped 
# together for the network analysis.  0 = data not available or not removed / 
# mitigated. 
# WaterbodyAcres: area in acres of waterbody associated with dam. -1 = no 
# associated waterbody

# Save the cleaned dataset to a CSV file for future use:
write_excel_csv(clean_NACC, paste(getwd(),"/Datasets/Cleaned/clean_NACC.csv", sep = ""))


# NOTES: 
# Habitat_Type = "tidal tributary/creek/river"
# Restoration_Technique = "hydrologic restoration" 
# All projects were dam removal of a stream, and the associated acres_restored
# represents the area in acres of waterbody associated with dam

 }

# ------------------------------------------------------------------------------
# DWH Dataset  ----------------------------
# ------------------------------------------------------------------------------
  
  {

# DWH data -----
clean_DWH <- raw_DWH %>% filter(
                                # Keep only projects that are not categorized as science or other 
                                !`Project Category` %in% c("Science","Other") &
                                # Keep only projects that are not categorized as planning, programmatic, environmental research, monitoring and observations
                                !`Primary Project Action` %in% c("Planning", "Programmatic","Environmental Research","Monitoring and Observations") &
                                # Keep only projects that are not categorized as human and social and human/institutional capacity (these are not restoration projects) and also remove projects that are categorized as human and social but do not have a source unique id ()
                                !(`Project Category` %in% c("Human and Social") & `Primary Targeted Resource` %in% c("Human and/or Institutional Capacity")  & !`OBJECTID`  %in%  c("35482","35483","35282")) &
                                # Remove all projects that have Stormwater in the project name except for projects that have additional habitat restoration actions stated in teh project description 
                                !(str_detect(`Project Name`, regex("stormwater", ignore_case = TRUE)) & !`OBJECTID`  %in%  c("36893")) &
                                # Remove all projects that have septic in the project name 
                                !(str_detect(`Project Name`, regex("Septic", ignore_case = TRUE))) & 
                                # Remove projects that have 'Planning' in project name except for projects that include implementation 
                                !(str_detect(`Project Name`, regex("Planning", ignore_case = TRUE)) & !`OBJECTID`  %in%  c("36483","36246")) &
                                # Remove projects that have 'sewer' in project name
                                !(str_detect(`Project Name`, regex("Sewer", ignore_case = TRUE))) &
                                # Remove projects that have terms in project description, except for projects that include restoration or socioeconomic benefits: 
                                !(str_detect(`Description`, regex("Sewer|septic|stormwater", ignore_case = TRUE)) & !`OBJECTID`  %in%  c("35501","35502","35717","35732","35750","35751","35863","35877","36016","36019","36175","36186","36347","36609","36893")), 
                                # Remove projects focused exclusively on wastewater 
                                !(str_detect(`Description`, regex("wastewater", ignore_case = TRUE))), 
                                # Remove projects clearly outside spatial boundaries: 
                                !`OBJECTID`  %in%  c("36925","36883","36445","36022","36451"), 
                                # Remove projects that are scientific studies or monitoring/feasibility studies: 
                                !`OBJECTID`  %in%  c("36936","36889","36599","36603","36454","36446","36444","36351","35630","35813","35818","35899","35984"), 
                                # Remove projects that are program development or design projects: 
                                !`OBJECTID`  %in%  c("36860","36857","36716","36699","36624","36534","36349","35482","35483","35468","35496","35740","35747"),
                                # Remove projects that exclusively fund construction for research/non-public buildings (not enhancing public access), sportfish facility, or ferry boats: 
                                !`OBJECTID`  %in%  c("36285","35741","36438","36452","36030")
                                ) %>%
  rename(Original_Project_ID = `OBJECTID`,
         Project_Name = `Project Name`,
         Project_Description = `Description`,
         Primary_Project_Action = `Primary Project Action`,
         Start_Year = `Award Year`,
         Exp_Completion_Year = `Anticipated Project Completion Year`,
         Habitat_Type = `Primary Targeted Resource`,
         Acres_Protected = `Acres Acquired`,
         Miles_Restored = `Restoration Mileage`,
         Feet_Restored = `Restoration Feet`,
         Funding_Program = `Funding Program`,
         Legislation = `Controlling Documents`,
         Lead_Implementer = `Implementing Organization`,
         Partners = `Other Partners`,
         Project_URL = Link,
         Legislation_Funding = `Dollar Amount`) %>%
  rowwise() %>%
  mutate(
         # Assign the main funding source based on the largest funding contribution.
         # If the DWH funding amount is greater than or equal to the leveraged funds,
         # use the DWH funder. Otherwise, compare the secondary funding amount
         # (Dollar Amount 2) to the DWH funding amount. If the secondary funding
         # amount is larger, use Funder 2; if not, use the DWH funder.
         Main_Funding_Source = case_when(
          Legislation_Funding >= `Total Leveraged Funds` ~ `DWH Funder`,
          Legislation_Funding < `Total Leveraged Funds` &
            `Dollar Amount 2` > Legislation_Funding ~ `Funder Name 2`,
          Legislation_Funding < `Total Leveraged Funds` &
            `Dollar Amount 2` <= Legislation_Funding ~ `DWH Funder`,
          TRUE ~ `DWH Funder`),
        
         # If Funder Name 2 becomes the main funding source then 1) remove it from 
         # Partners and 2) add DWH Funder to Partners
         Partners = case_when(
          Main_Funding_Source == `Funder Name 2` &
            !is.na(`Funder Name 2`) ~ {
              # Handle missing/None partner lists
              if (is.na(Partners) || Partners == "None") {`DWH Funder`
              } else {
                p <- trimws(unlist(strsplit(Partners, ";")))
                # Remove Funder Name 2 if present
                p <- p[p != `Funder Name 2`]
                # Add DWH Funder
                p <- unique(c(p, `DWH Funder`))
                paste(p, collapse = "; ") } },
          TRUE ~ Partners),
         
         Project_URL = str_extract(Project_URL, "http[^\"\\s]+"), # Reformat 
         Total_Project_Cost = `Total Leveraged Funds` + Legislation_Funding, # Calculate total project cost 
         Acres_Restored = `Land Restoration Acreage` + `Aquatic Restoration Acreage`, # Calculate total restored acreage 
         Start_Year = ifelse(Start_Year== 0, NA,Start_Year), 
         Exp_Completion_Year = as.numeric(ifelse(Exp_Completion_Year == 0, NA, Exp_Completion_Year)),
         Data_Source = "DWH",
         Restoration_Technique = NA) %>%
select(c(Data_Source, Original_Project_ID, Project_Name, Project_Description, County, Start_Year, Exp_Completion_Year, Primary_Project_Action,
         Habitat_Type, Restoration_Technique, Acres_Restored, Acres_Protected, Miles_Restored, Feet_Restored, Main_Funding_Source, Funding_Program, Legislation,
         Legislation_Funding, Total_Project_Cost, Lead_Implementer, Partners, Latitude, Longitude, Project_URL)) 
 

# Format funding information: 
# In clean_DWH, if the value in Funding_Program = X, replace the value in column `Legislation` with `Y`: 
clean_DWH <- clean_DWH %>%
  mutate(Legislation = ifelse(Funding_Program == "Natural Resource Damage Assessment NRDA", "OPA of 1990", Legislation),
         Legislation = ifelse(Funding_Program == "NFWF Gulf Environmental Benefit Fund GEBF", NA , Legislation),
         Legislation = ifelse(Funding_Program == "MOEX Supplemental Environmental Projects", NA, Legislation),
         Legislation = ifelse(Funding_Program == "NFWF Recovered Oil Fund for Wildlife", "voluntary agreement", Legislation))

# If the value in column `Legislation` is NA, replace the value in column `Legislation_Funding` with NA: 
clean_DWH <- clean_DWH %>%
  mutate(Legislation_Funding = ifelse(is.na(Legislation), NA, Legislation_Funding))

 
# Clean up and fill in the habitat type and restoration technique columns based 
# on Primary_Project_Action and project description: 

clean_DWH <- clean_DWH %>%
  mutate(
    
    Restoration_Technique = case_when(
      
      Primary_Project_Action == "Education and Outreach" ~ "education/recreation",
      
      Primary_Project_Action == "Land Acquisition/Protection" ~ "conservation/preservation",
      
      str_detect(Project_Description, regex("Artificial reef", ignore_case = TRUE)) ~ "reef construction",
      
      # For some reason these artificial reef projects didn't pop up from search string
      Original_Project_ID %in% c("36259","35763") ~ "reef construction",
      
      # The ones excluded have clearly stated habitat restoration in project description
      Primary_Project_Action == "Engineering and/or Construction" &
        Habitat_Type == "Recreational Resources" &
        !Original_Project_ID %in% c("36022","36037","36039","36040","36060","36451") ~ "education/recreation",
      
      Primary_Project_Action == "Tourism Development and Promotion" &
        Habitat_Type == "Recreational Resources" ~ "education/recreation",
      
      Primary_Project_Action == "Engineering and/or Construction" &
        Habitat_Type == "Infrastructure" &
        !Original_Project_ID %in% c("35670") ~ "education/recreation",
      
      TRUE ~ Restoration_Technique
    ),
    
    Habitat_Type = case_when(
      
      Primary_Project_Action == "Education and Outreach" ~ NA_character_,
      
      str_detect(Project_Description, regex("Artificial reef", ignore_case = TRUE)) ~ "hard bottom",
      
      # For some reason these artificial reef projects didn't pop up from search string
      Original_Project_ID %in% c("36259","35763") ~ "hard bottom",
      
      Primary_Project_Action == "Engineering and/or Construction" &
        Habitat_Type %in% c("Recreational Resources","Infrastructure") ~ NA_character_,
      
      TRUE ~ Habitat_Type
    )
  )

# NOTES: 
# Manual review of project descriptions resulted in the initial round of exclusion of projects above 


# Export and manually fill in remaining with habitat and restoration technique from the project description: 
write_csv(clean_DWH, paste0(getwd(),"/Datasets/Supporting Documents/DWH/DWH_preprocessed.csv"))

# Re-upload with updated dataset: 
clean_DWH <- read_excel(paste0(getwd(),"/Datasets/Supporting Documents/DWH/DWH_processed.xlsm")) 

# Remove Primary_Project_Action: 
clean_DWH <- clean_DWH %>% select(-Primary_Project_Action) %>% 
  mutate(across(where(is.character),
                ~ na_if(na_if(na_if(., "NA"), "N/A"), "")))

# Format dates correctly: 
clean_DWH$Exp_Completion_Year <- as.numeric(clean_DWH$Exp_Completion_Year)

# Fix encoding issues with function fix_encoding: 
clean_DWH <- clean_DWH %>% mutate(across(where(is.character), fix_encoding))


# Save the cleaned dataset to a CSV file for future use:
write_excel_csv(clean_DWH, paste(getwd(),"/Datasets/Cleaned/clean_DWH.csv", sep = ""))



  }
  
} # end of run to clean and standardize all individual datasets 

# ==============================================================================
# ==============================================================================
# COMBINE AND STANDARDIZE MERGED MASTER DATASET 
# ==============================================================================
# ==============================================================================
{
# ------------------------------------------------------------------------------
# COMBINE ALL DATASETS TOGETHER -------
# ------------------------------------------------------------------------------
  
{
#rm(db_list_clean,db_list_clean_fixed)

# Make list of databases that are cleaned ( have 'clean_')
db_list_clean <- mget(ls(pattern = "clean_"))

# Check to standardize parameters across all datasets
db_list_clean_fixed <- map(db_list_clean, ~ mutate(., 
                                                   Original_Project_ID = if ("Original_Project_ID" %in% names(.)) as.character(Original_Project_ID) else NA_character_,
                                                   Start_Year = if ("Start_Year" %in% names(.)) as.numeric(Start_Year) else NA_real_,
                                                   Acres_Restored = if ("Acres_Restored" %in% names(.)) as.numeric(Acres_Restored) else NA_real_,
                                                   Acres_Protected = if ("Acres_Protected" %in% names(.)) as.numeric(Acres_Protected) else NA_real_,
                                                   Miles_Restored = if ("Miles_Restored" %in% names(.)) as.numeric(Miles_Restored) else NA_real_,
                                                   Feet_Restored = if ("Feet_Restored" %in% names(.)) as.numeric(Feet_Restored) else NA_real_,
                                                   Debris_Removed = if ("Debris_Removed" %in% names(.)) as.numeric(Debris_Removed) else NA_real_,
                                                   Total_Project_Cost = suppressWarnings(if ("Total_Project_Cost" %in% names(.)) as.numeric(Total_Project_Cost) else NA_real_),
                                                   Legislation_Funding = if ("Legislation_Funding" %in% names(.)) as.numeric(Legislation_Funding) else NA_real_,
                                                   Latitude = if ("Latitude" %in% names(.)) as.character(Latitude) else NA_character_,
                                                   Longitude = if ("Longitude" %in% names(.)) as.character(Longitude) else NA_character_
)) 


# List out column names for each database listed in db_list_clean: 


# Bind rows
master_db <- bind_rows(db_list_clean_fixed) 

# Reorganize columns by preference: 
master_db <- master_db %>%
  select ("Project_Group_ID","Original_Project_ID","Data_Source","Project_Name","Project_Description",
          "County","Congressional_District","Longitude","Latitude", "Project_Status",
          "Start_Year","Completion_Year","Exp_Completion_Year","Habitat_Description","Habitat_Type",
          "Restoration_Technique", "Acres_Restored","Acres_Protected", "Miles_Restored", "Miles_Protected", 
          "Feet_Restored", "Debris_Removed","Species_Benefited",
           "Socioeconomic_Jobs_Created", "Socioeconomic_Avoided_Travel_Losses", 
          "Socioeconomic_Avoided_Damage_Losses", "Socioeconomic_Properties_Benefitted", 
          "Main_Funding_Source",
          "Funding_Program","Legislation","Legislation_Funding","Total_Project_Cost", 
          "Lead_Implementer", "Partners", "Permit_Type","Agency_Action",
          "Permit_ApprovalDate","Permit_ExpirationDate","Point_of_Contact_Email","Project_URL",everything())

# Clean any encoding text issues: 
master_db <- master_db %>% mutate(across(where(is.character), fix_encoding))


length(unique(colnames(master_db)))
unique(colnames(master_db))

rm(db_list_clean,db_list_clean_fixed)


}
  
nrow(master_db)

# ------------------------------------------------------------------------------
# Standardize categories for variables Habitat Type and Restoration Technique  
# ------------------------------------------------------------------------------

{
  
# load libraries   
library(dplyr)
library(tidyr)
library(stringr)
library(readxl)
#install.packages("googlesheets4")
library(googlesheets4)
  
  # make sure general access is set to anyone with link can view
  # gs4_deauth()   # clears any existing token
  # gs4_auth()     # prompts you to sign in again
  
  # IF anyone needs re-authorization: 
  #gs4_auth(scopes = "https://www.googleapis.com/auth/spreadsheets.readonly")
  
  
habrestcategory <- read_sheet("https://docs.google.com/spreadsheets/d/1IukpdRopwmMeQDunSW5YHefHleh_Mz0nixNSzNHy3Uk/edit?usp=share_link", sheet = "final_categories") 

# Standardize text (lowercase) and if the habitat type value has a comma
# (multiple habitats listed) then replace with 'multiple': -----------------
master_db <- master_db %>%
  mutate(
    Habitat_Type = tolower(Habitat_Type),
    Restoration_Technique = tolower(Restoration_Technique))
  
hab_lookup <- habrestcategory %>%
    filter(Variable == "HabitatType") %>%
    select(Terms, Categories)
  
rest_lookup <- habrestcategory %>%
    filter(Variable == "RestorationTechnique") %>%
    select(Terms, Categories)
  
# Standardize Habitat Type --------------

# Counts of unique values in Habitat Type before standardization:
pre_standardization_hab_counts <- length(unique(master_db$Habitat_Type))

master_db <- master_db %>%
  left_join(hab_lookup, by = c("Habitat_Type" = "Terms")) %>%
  mutate(Habitat_Type = coalesce(Categories, Habitat_Type)) %>%
  select(-Categories)

# Q/A check of unmatched techniques
unmatched_habitat <- master_db %>%
  anti_join(hab_lookup, by = c("Habitat_Type" = "Terms")) %>%
  distinct(Habitat_Type)
unmatched_habitat

# make a table of number of projects for each habitat type
table(master_db$Habitat_Type)


# Standardize Restoration Type ----------

# organize alphabetically: 
unique(master_db$Restoration_Technique) %>% sort()

# Subset because multiple techniques can be listed for a given project and split
# comma-separated techniques into multiple columns
dataset_sub <- master_db %>%
  mutate(temp_row_id = row_number()) %>% # create temporary row id 
  select(temp_row_id, Restoration_Technique) %>%
  separate(
    Restoration_Technique,
    into = paste0("Restoration_Technique_", 1:10),
    sep = ",",
    fill = "right")

# Pivot the technique columns to long format and join lookup table 
dataset_sub <- dataset_sub %>%
  pivot_longer(
    cols = starts_with("Restoration_Technique_"),
    names_to = "tech_col",
    values_to = "Term") %>%
  mutate(Term = trimws(Term))  %>%
  left_join(rest_lookup, by = c("Term" = "Terms"))

# Counts of unique values in Restoration Technique before standardization:
pre_standardization_tech_counts <- length(unique(dataset_sub$Term))

# Q/A check of unmatched techniques
unmatched_technique <- dataset_sub %>%
  filter(!is.na(Term)) %>%
  anti_join(rest_lookup, by = c("Term" = "Terms")) %>%
  count(Term, sort = TRUE)
unmatched_technique

# Replace all unmatched terms with "other": 
dataset_sub <- dataset_sub %>%
  mutate(Term = ifelse(Term %in% unmatched_technique$Term, "other", Term))


# Replace matched terms with categories and create final dataset with one row
# per project and comma-separated list of techniques:
dataset_sub <- dataset_sub %>%
  mutate(Term = coalesce(Categories, Term)) %>%
  filter(!is.na(Term)) %>%                 # remove empty cells
  distinct(temp_row_id, Term) %>%    # remove duplicates within project
  group_by(temp_row_id) %>%
  summarise(
    Restoration_Technique = paste(Term, collapse = ", "),
    .groups = "drop")

# Replace the original Restoration_Technique column in master_db with the 
# standardized one from dataset_sub:
master_db <- master_db %>%
  mutate(temp_row_id = row_number()) %>% # create temporary row id 
  select(-Restoration_Technique) %>%
  left_join(dataset_sub, by = "temp_row_id") %>% 
  relocate(Restoration_Technique, .after = Habitat_Type) %>%
  select(-temp_row_id)
  


# Counts of unique values in Habitat Type and Restoration Technique after 
# standardization:
post_standardization_hab_counts <- length(unique(hab_lookup$Categories))
post_standardization_tech_counts <- length(unique(rest_lookup$Categories))

# Create table of counts of unique values before and after standardization:
standardization_summary <- tibble(
  Variable = c("Habitat Type", "Restoration Technique"),
  Unique_Values_Before = c(pre_standardization_hab_counts, pre_standardization_tech_counts),
  Unique_Values_After = c(post_standardization_hab_counts, post_standardization_tech_counts))
print(standardization_summary)

}
  
# ------------------------------------------------------------------------------
# Standardize categories for variables Main Funding Source and Lead Implementer 
# ------------------------------------------------------------------------------

{
    #install.packages("googlesheets4")
  library(googlesheets4)
  
  # make sure general access is set to anyone with link can view
   # gs4_deauth()   # clears any existing token
   # gs4_auth()     # prompts you to sign in again
  
  # IF anyone needs re-authorization: 
    #gs4_auth(scopes = "https://www.googleapis.com/auth/spreadsheets.readonly")
  
  mainfundingcategory <- read_sheet("https://docs.google.com/spreadsheets/d/1LNRASyruLBBb0TsupHiJDS_t6LWUtKeQgfl0l-FKNBk/edit?gid=0#gid=0")
  leadimplementercategory <- read_sheet("https://docs.google.com/spreadsheets/d/1XYNDd_s7ttw1p1c8wMR7VuqCAib-UyUHd9ljlz8aQ00/edit?gid=0#gid=0")
  
  # Create temporary matching variables to maintain original inputs formatting
  master_db <- master_db %>%
    mutate(Main_Funding_Source_match = Main_Funding_Source %>%
        str_squish() %>% str_to_lower(),
      Lead_Implementer_match = Lead_Implementer %>% 
        str_squish() %>% str_to_lower())
  
  # Create matching variable for Main Funding Source lookup table
  mainfundingcategory <- mainfundingcategory %>%
    mutate(Main_Funding_Source_match = Main_Funding_Source %>%
        str_squish() %>% str_to_lower()) %>%
    distinct(Main_Funding_Source_match, Main_Funding_Category, .keep_all = TRUE)
  
  # Create matching variable for Lead Implementer lookup table
  leadimplementercategory <- leadimplementercategory %>%
    mutate(Lead_Implementer_match = Lead_Implementer %>%
        str_squish() %>% str_to_lower()) %>%
    distinct(Lead_Implementer_match, Lead_Implementer_Category, .keep_all = TRUE)
  
  # Create Main Funding Category
  master_db <- master_db %>%
    left_join(mainfundingcategory %>%
        select(Main_Funding_Source_match, Main_Funding_Category),
      by = "Main_Funding_Source_match") %>%
    relocate(Main_Funding_Category, .after = Main_Funding_Source)
  
  # Create Lead Implementer Category
  master_db <- master_db %>%
    left_join(leadimplementercategory %>%
        select(Lead_Implementer_match,Lead_Implementer_Category),
      by = "Lead_Implementer_match") %>%
    relocate(Lead_Implementer_Category, .after = Lead_Implementer)
  
  # Remove temporary matching variables
  master_db <- master_db %>% 
    select(-Main_Funding_Source_match,-Lead_Implementer_match)
  
  }
  
# ------------------------------------------------------------------------------
# Standardize categories for variable County  
# ------------------------------------------------------------------------------

{
# Clean and format the inputs for County 
master_db <- master_db %>%
  mutate(
    County = str_to_title(County), # make lowercase except for the first letter of a word
    County = str_remove_all(County, "\\bCount(y|ies)\\b"), # remove term County or Counties anywhere
    County = str_replace_all(County, ";", ","),     # replace ; with ,
    County = str_replace_all(County, "\\s+And\\s+", ","),    # replace "and" with comma
    County = str_replace_all(County, ",{2,}", ", "),  # remove double commas created by cleaning
    County = str_replace_all(County, "\\s+,", ","),   # remove spaces before commas
    County = str_squish(County),     # trim whitespace
    County = str_remove_all(County, "^,|,$"))     # remove leading/trailing commas

# Check results 
unique(master_db$County) %>% sort()

# Clean up the inputs for County that are not defined, offshore, or multiple counties: 
master_db <- master_db %>%
  mutate(County = ifelse(County == "Not Defined", NA_character_, County)) %>%
  mutate(County = ifelse(County == "Offshore", NA_character_, County)) %>%
  mutate(County = ifelse(County == "Multiple", NA_character_, County))
  
# Address projects that listed multiple counties: 
# For inputs of variable County that contain multiple counties, create a new
# column called County_Multiple that transfers the information from that
# original County row and replaces it with NA:
master_db <- master_db %>%
  mutate(
    County_Multiple = ifelse(str_detect(County, ","), County, NA_character_),
    County = ifelse(str_detect(County, ","), NA_character_, County)
  ) %>%
  relocate(County_Multiple, .after = County)
}
  
# ------------------------------------------------------------------------------
# Standardize size categories for variables Acres_Restored and Miles_Restored   
# ------------------------------------------------------------------------------

{

# Create size categorical bins for Acres restored: 
master_db <- master_db %>%
  mutate(
      Acres_Restored_Category = case_when(
      Acres_Restored > 0 & Acres_Restored < 1 ~ "<1 acres",
      Acres_Restored >= 1 & Acres_Restored < 5 ~ "1 - <5 acres",
      Acres_Restored >= 5 & Acres_Restored < 50 ~ "5- <50 acres",
      Acres_Restored >= 50 ~ "50+ acres",
      TRUE ~ NA_character_ # for any missing or invalid values
      )) %>% 
    relocate(Acres_Restored_Category, .after = Acres_Restored)

# Create size categorical bins for miles restored: 
master_db <- master_db %>%
  mutate(
    Miles_Restored = ifelse(Miles_Restored == 0, NA, Miles_Restored),
    Miles_Restored_Category = case_when(
      Miles_Restored > 0 & Miles_Restored < 1 ~ "<1 miles",
      Miles_Restored >= 1 & Miles_Restored < 5 ~ "1-5 miles",
      Miles_Restored >= 5 ~ "5+ miles",
      TRUE ~ NA_character_ # for any missing or invalid values
    )) %>% 
  relocate(Miles_Restored_Category, .after = Miles_Restored)

}
  
# ------------------------------------------------------------------------------
# Standardize numeric variables (coordinates, funding, feet to miles conversion)
# ------------------------------------------------------------------------------

{
# Make Latitude and Longitude numeric (if NA character than change to NA numeric):
master_db <- master_db %>%
  mutate(Latitude = as.numeric(Latitude), Longitude = as.numeric(Longitude))


# Standardize financial funding variables: 
master_db <- master_db %>%
  mutate(Total_Project_Cost = abs(as.numeric(Total_Project_Cost)),
         Legislation_Funding = abs(as.numeric(Legislation_Funding)),
         
         # Standardize from unit of millions to unit of dollars: 
         Socioeconomic_Avoided_Damage_Losses = as.numeric(Socioeconomic_Avoided_Damage_Losses),
         Socioeconomic_Avoided_Damage_Losses = ifelse(!is.na(Socioeconomic_Avoided_Damage_Losses), 
                                                      Socioeconomic_Avoided_Damage_Losses * 1000000, NA),
         # Standardize from unit of thousands to unit of dollars: 
         Socioeconomic_Avoided_Travel_Losses = as.numeric(Socioeconomic_Avoided_Travel_Losses),
         Socioeconomic_Avoided_Travel_Losses = ifelse(!is.na(Socioeconomic_Avoided_Travel_Losses), 
                                                      Socioeconomic_Avoided_Travel_Losses * 1000, NA))


# Calculate feet (Feet_Restored) into miles (Miles_Restored), and add that value
# to whatever value is in the Miles_Restored column (if any):
master_db <- master_db %>%
  mutate(
    Feet_Restored = as.numeric(Feet_Restored),
    Miles_Restored = as.numeric(Miles_Restored),
    Miles_From_Feet = ifelse(!is.na(Feet_Restored), Feet_Restored / 5280, NA),
    Total_Miles_Restored = coalesce(Miles_Restored, 0) + coalesce(Miles_From_Feet, 0)
  ) %>%
  select(-c(Miles_From_Feet, Miles_Restored,Feet_Restored)) %>%  # remove intermediate column
  rename(Miles_Restored = Total_Miles_Restored) %>% # rename to indicate standardized variable
  relocate(Miles_Restored, .after = Acres_Protected)

}

# ------------------------------------------------------------------------------
# Save standardized master database 
# ------------------------------------------------------------------------------


# save as Rdata
save(master_db, file = paste(getwd(),"/Florida Estuarine Restoration Database/master_db.Rdata",sep = ""))


} # end of run to combine and standardize master database 

