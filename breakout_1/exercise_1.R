library(ellmer)
library(tidyverse)
library(gt)

# Pull in helper functions and prompts
source("./utils.R")
source("./breakout_1/prompts_1.R")

# Load CDISC data from the pharmaverseadam package
adsl <- pharmaverseadam::adsl
adae <- pharmaverseadam::adae

# Create chat objects for the production and QC agents.
# Note we're keeping these separate so that they don't share
# chat histories with each other and can preserve only the specific contexts
# that we want them to have.
prod_agent_chat <- chat_anthropic(
  model = "claude-sonnet-4-5-20250929",
)

# prod_agent_chat <- chat_openai(
#   model="gpt-5"
# )

qc_agent_chat <- chat_anthropic(
  model = "claude-sonnet-4-5-20250929",
)

# qc_agent_chat <= chat_openai(
#   model="gpt-5"
# )

# Use a helper function to create the production prompt. You can find each of the 
# indepdent pieces of this prompt within the prompts.R file. 
prod_prompt <- prod_generate_prompt(
  gen_purpose,
  get_data_context(), # This is a helper function that gives the context of the data to the LLM.
  gen_packages,
  gen_style_rules,
  formatting_rules,
  task = "Write me code to create a demographics table" # Change this to whatever you want to do! 
)

# Look at the full text of the prompt
# See something that you want to change? You can edit any of the components
cat(prod_prompt)

# Submit the prompt to the LLM. Set echo to TRUE if you want to watch the streamed response
prod_response <- prod_agent_chat$chat(prod_prompt, echo=FALSE)

# Here's what the LLM returned
cat(prod_response)

prod_code <- extract_code_from_response(prod_response) # This function pulls out the code so we can use it in the QC agent
prod_text <- extract_text_from_response(prod_response) # If you want to see what the LLM had to say, you can print this variable

# Now build the prompt to submit to the QC agent. 
# We'll provide a lot of the same information, but now we have code that can be reviewed.
# What do we want the QC agent to look for? You can look at the qc_quality_criteria variable in prompts.R 
# to try to tune what the evaluation criteria are. 
qc_prompt <- qc_generate_prompt(
  qc_purpose,
  get_data_context(), # This is a helper function that gives the context of the data to the LLM.
  gen_packages,
  qc_quality_criteria,
  formatting_rules, 
  gen_style_rules,
  "Review and rewrite the provided code for the defined quality criteria. Provide an improved version of the code.",
  prod_code
)

# Submit the prompt to the LLM. Set echo to TRUE if you want to watch the streamed response
qc_response <- qc_agent_chat$chat(qc_prompt, echo=FALSE)


qc_code <- extract_code_from_response(qc_response) # This function pulls out the code 
qc_text <- extract_text_from_response(qc_response) # If you want to see what the LLM had to say, you can print this variable

# What did the LLM find?
cat(qc_text)

# Let's try to run the code!
qc_result <- tryCatch(
  {
    # This runs the code that we captured from the LLM
    list(
      success=TRUE,
      output = eval(parse(text = qc_code))
    )
  },
  # This 
  error = function(e) {

    err <- sprintf("%s\n%s", e$message, paste(as.character(traceback()), collapse="\n"))

    return(
      list(
        success = FALSE, 
        output = ":(",
        error = err
      )
    )
  }
)

# Check the result - success will open up in the viewer! 
qc_result$output

# Follow up and ask the LLM to fix the error
if (!qc_result$success) {
  qc_agent_chat$chat(
    sprintf("The code encountered an error:\n %s\n %s", 
    qc_result$error, 
    paste(as.character(traceback()), collapse="\n")), echo=FALSE
  )

  qc_code <- extract_code_from_response(qc_response) 
  
  # Try again
  eval(parse(text = qc_code))
}
