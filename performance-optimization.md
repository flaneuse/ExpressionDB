## Performance issues with large datasets

### Preface
In August/September, I rebuilt the filtering functioncs within ExpressionDB to add functionality and streamline maintenance.  Major changes included:
- switching to stringr string detection for gene symbols
- adding in capabilities to search for gene name
- nesting gene ontologies within a data frame rather than having them as a single string to be more logical, and avoid regex issues.
- separating things into functions for cleaner code
- added in checks to prevent cross-contamination between functions

However, in doing so, the memory demands on the system are much greater for some reason.  Herein are my notes testing why this could be.

### Observations
* Works fine with smaller datasets, but the rat and mouse MuscleDB breaks it.
* Platform independent; a rat version of ExpressionDB breaks on 2017 Macbook Pro, Linux server computer, and Windows machine.
* Error manifests in several ways: RStudio fatal error, long processing time, Rstudio going into infinite loop that has to be interrupted.
* Easiest place to observe the problem is by turning on advanced filtering.  --> crash!
* General data manipulation is a problem.  Though filterExpr.R seems to be the source of the majority of the issues, the data transformation within comparison.R still is a problem.
* Original muscleDB code is fine with same data.
* Crash report from RStudio:
```
CLIENT EXCEPTION (rsession-laurahughes): (TypeError) : undefined is not an object (evaluating 'this.a.a.r.row');|||org/rstudio/studio/client/workbench/views/source/editors/text/r/SignatureToolTipManager.java#134::execute|||com/google/gwt/core/client/impl/SchedulerImpl.java#167::runScheduledTasks|||com/google/gwt/core/client/impl/SchedulerImpl.java#338::flushPostEventPumpCommands|||com/google/gwt/core/client/impl/SchedulerImpl.java#76::execute|||com/google/gwt/core/client/impl/SchedulerImpl.java#140::execute|||com/google/gwt/core/client/impl/Impl.java#244::apply|||com/google/gwt/core/client/impl/Impl.java#283::entry0|||http://127.0.0.1:39302/#-1::anonymous|||com/google/gwt/cell/client/AbstractEditableCell.java#41::viewDataMap|||Client-ID: 33e600bb-c1b1-46bf-b562-ab5cba070b0e|||User-Agent: Mozilla/5.0 (Macintosh  Intel Mac OS X 10_12_6) AppleWebKit/603.3.8 (KHTML, like Gecko)
```
* Crash report after updating RStudio:
```
ERROR system error 41 (Protocol wrong type for socket) [request-uri=/grid_data]; OCCURRED AT: virtual void rstudio::session::HttpConnectionImpl<boost::asio::ip::tcp>::sendResponse(const core::http::Response &) [ProtocolType = boost::asio::ip::tcp] /Users/rstudio/rstudio/src/cpp/session/http/SessionHttpConnectionImpl.hpp:93; LOGGED FROM: virtual void rstudio::session::HttpConnectionImpl<boost::asio::ip::tcp>::sendResponse(const core::http::Response &) [ProtocolType = boost::asio::ip::tcp] /Users/rstudio/rstudio/src/cpp/session/http/SessionHttpConnectionImpl.hpp:98
```

### Hypotheses / Tests
Unless otherwise specified, primary test is applying advanced filtering to the full rat dataset.
1. **filterExpr.R is bad**

__Test__: commented out all of filterExpr and just returned the full dataset.

__Result__: Basically, everything seemed good except for comparison plot, which still took an obscene amount of time. Highlights the fact that data manipulation seems to be a problem.


2. **Nesting GOs is bad**

__Test__: Loaded processed rat expression data, mutated GO to be a single simple string.

__Result__: Crash.

3. **data.table has an underlying error that creates problems**

__Hypothesis__: Googling the Client Exception error --> [discussion about incompatibility of data.table and Rstudio](https://community.rstudio.com/t/rstudio-v1-1-crashes-unable-to-establish-connection-with-r-session/2039/8) in recent versions. Suggesion is that the versions of data.table that are 1.10.4-1, 1.10.4-2 are unstable and 1.10.4 and 1.10.5 are more stable. However, 1.10.4 was used during development.

__Test__: Commented out data.table and heatmaply (plotly requires data.table) + references in ui.R, server.R to heatmap function.

__Result__: Crash.

4. **Check that it's not a local problem**

__Test__: deploy to shinyapps.io. 

__Result__: still very slow

5. **Update Rstudio to Version 1.1.383**

__Result__: things actually seem faster, but still crash.

### Stage 2.
This seems to be going nowhere, so off to identify the source of the error.
Inserting in print markers to identify the line of code where the filterExpr.R fails.

The call to `filter_gene` is possibly unstable.
```
filtered = filtered %>% 
filter_gene(filteredTranscripts)
```

The whole of filter_gene is thus:
```
filter_gene = function(df, filteredDF) {
filter_arg = paste0(data_unique_id, " %in% list('",  paste(filteredDF, collapse = "','"), "')")


df %>% filter_(filter_arg)
}
```

... which exposes a weakness in the  ```paste(filteredDF, collapse = "','")``` call.
For the ratdb, filteredDF is a list of 124820 IDs from the dataset.  A big number.  Also 4x bigger than it needs to be, since I didn't get the *unique* values of the IDs.

Fixing ```filter_expr``` to account for this.
```
filter_expr = function(filtered) {

      filtered %>%
        filter(expr <= input$maxExprVal,
               expr >= input$minExprVal) %>% 
        pull(data_unique_id) %>% 
        unique()
         
```

... but there's still > 31k genes to filter.  The actual application of the filter (```df %>% filter_(filter_arg)```) is where it fails.

But there's no reason why it needs to be applied, if no real filtering is happening. As a sidenote, this two-stage filtering is necessary because we want to include all data from a gene that has ANY expression within the limits. So, for a hypothetical geneX, it might have EDL expression of 0, eye of 10, and left ventricle of 1000.  If we set the expression to be RPKM between 10-100, we would have a holey plot, where the EDL and LV data are missing. Not ideal.

#### The first fix:
Okay, write an ```if``` statement that checks if filtering needs to happen. If not, move on. This solves the problem... however, if you have a narrow filter applied, you run into the same problem.

On my machine (R version 3.4.1 (2017-06-30)
Rstudio: 1.1.383
Platform: x86_64-apple-darwin15.6.0 (64-bit)
Running under: macOS Sierra 10.12.6
3.5 GHz Intel Core i7
16 GB 2133 MHz LPDDR3), the filter seemed to break around > 20389 transcripts. For rat expression dataset, > 0.5 RPKM okay; > 0.4 bad.

#### The more general fix:
Resort to base R for the filtering.

```
      if(length(filteredDF) != nTranscripts) {
        
        # Pulling out the base R....
        df = df[df$transcript %in% filteredDF,]
      }
```    

### Fixing ```comparison.R```
There's also some instability/slowness from comparison.R. It appears that's in part from the double filtering that happens:
```
        filtered = filtered %>% 
          filter_gene(filteredTranscripts) %>% 
          filter_gene(filteredFC)
          ```

```filteredFC``` also needs a check for uniqueness:
        ```
        filteredFC = left_join(filtered, relExpr,         # Safer way: doing a many-to-one merge in:
                               by = setNames(data_unique_id, data_unique_id)) %>% 
          mutate(`fold change`= expr/relExpr) %>%         # calc fold change
          filter(`fold change` >= input$foldChange) %>%       # filter FC
          pull(data_unique_id) %>% 
          unique()
          ```
        