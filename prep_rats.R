
# Import and clean rat expression data, before running through thr --------

# Expression data is from 5 June 2017
# Scott Lewis previously merged the transcript ids with their gene names, symbols, ontologies
# However, expression data had error in formula
# Merging the corrected expression data along with the gene names.
# Laura Hughes, 25 October 2017, laura.d.hughes@gmail.com

library(tidyverse)
library(readxl)
library(stringr)

# Import data -------------------------------------------------------------
# file containing ontological terms
ont = read_excel('~/Dropbox/Muscle Transcriptome Atlas/RUM_Re-analysis/Muscle_Re-run_Mapstats_Quantfiles/MT_Adjusted_TranscriptQuants_(RAT)+GeneNames+GO.xlsx', skip = 1)

ont = ont %>% 
  select(Transccript, Short.Name, Gene.Name, Gene.Symbol, Location) %>% 
  filter(!is.na(Transccript))


# file containing correct expression data
df = read_excel('data/MT_Adjusted_TranscriptQuants_(RAT).xlsx')

df = df %>% select(-contains('AVERAGE'), -contains('SEM'), -contains('X'))


# figure out which transcripts are excluded between two files -------------

setdiff(ont$Transccript, df$Transccript) # all match
ont$Transccript[duplicated(ont$Transccript)] # but there are ~ 1200 duplicated rows

# remove extra rows
ont = ont %>% distinct()


# merge -------------------------------------------------------------------

df = df %>% left_join(ont, by = c('Transccript', 'Location'))

df %>% count(is.na(Short.Name)) # Merge is succes if all short names match.  

df %>% distinct(Short.Name) %>% count()
# Short name is constant for all, though not unique
# The problem arises for ones with [[1]] -- sometimes there's a [[2]]




# cleanup -----------------------------------------------------------------
# Create a shorter but still distinct transcript name.
df = df %>% 
  separate(Transccript, into = c('first', 'second'), sep = '::::', remove = FALSE) %>% 
  mutate(short = str_replace_all(first, "\\,\\+transcript", ""),
         short = str_replace_all(short, "\\,\\-transcript", ""),
         short = str_replace_all(short, "\\(ensembl\\)", ""),
         short = str_replace_all(short, "\\(refseq\\)", ""))



df %>% distinct(short) %>% count() %>% pull() == 40316
df %>% distinct(Short.Name) %>% count() %>% pull() == 40316

# Clean up column names
df = df %>% rename(transcript = short, gene_id_go = Gene.Symbol) %>% 
  select(-Gene.Name, -Short.Name, -Location, -Transccript, -first, -second)

# save --------------------------------------------------------------------


# write subset for initial test
write_csv(df %>% sample_n(500), 'data/expr_rat_sample.csv')

write_csv(df, 'data/expr_rat_20170705.csv')
