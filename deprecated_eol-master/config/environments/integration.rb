#----------------------------------------------------------------
#                     integration.rb
# Environment specific settings for the Integration environment
#
# Settings specified here will override those in config/environment.rb
#
# # Configuration files are loaded in the following order with the settings
# in each file overriding the settings in prior files
#
# 1) config/environment.rb
# 2) config/environments/[Rails.env].rb
# 3) config/environments/[Rails.env]_eol_org.rb
# 4) config/environment_eol_org.rb
#---------------------------------------------------------------

# Allow debugger breakpoints:
require "ruby-debug"

# In the development environment your application's code is reloaded on
# every request.  This slows down response time but is perfect for
# development since you don't have to restart the webserver when you make
# code changes.
config.cache_classes = true

# Log error messages when you accidentally call methods on nil.
config.whiny_nils = false

# Allow breakpoints in mongrel:
require "ruby-debug"

# Show full error reports and disable caching
config.action_controller.consider_all_requests_local = false
config.action_controller.perform_caching             = false
config.action_view.debug_rjs                         = false

# email error reporting
config.action_mailer.raise_delivery_errors = false

# logging level
config.log_level = :debug
config.cache_store = :dalli_store
ActiveRecord::Base.logger = Logger.new(STDOUT)
ActionController::Base.logger = Logger.new(STDOUT)
ActiveSupport::Cache::MemCacheStore.logger = Logger.new(STDOUT)

# set to false turn off notification of exceptions via email
$EXCEPTION_NOTIFY=false

# set to true to enable recaptcha on registration and contact us form
$ENABLE_RECAPTCHA=false

# ANALYTICS CONFIGURATION
# Set ENABLE_ANALYTICS to true to enable google analytics.  The
# GOOGLE_ANALYTICS_ID must be set to the google analytics ID
# to use if analytics is enabled.
$ENABLE_ANALYTICS=false
$GOOGLE_ANALYTICS_ID="UA-3298646-1"


#This part of the code should stay at the bottom to ensure that www.eol.org - related settings override everything
begin
  require File.join(File.dirname(__FILE__), 'integration_eol_org')
rescue LoadError
  puts '*************WARNING: COULD NOT LOAD integration_eol_org FILE***********************'
end
