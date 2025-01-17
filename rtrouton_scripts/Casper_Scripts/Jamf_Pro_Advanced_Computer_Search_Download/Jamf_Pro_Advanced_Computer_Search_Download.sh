#!/bin/bash

# This script is designed to use the Jamf Pro API to identify the individual IDs of 
# the advanced computer searches stored on a Jamf Pro server then do the following:
#
# 1. Back up existing downloaded advanced computer search directory
# 2. Download the advanced computer search as XML
# 3. Identify the advanced computer search name
# 4. Save the advanced computer search to a specified directory

# If setting up a specific user account with limited rights, here are the required API privileges
# for the account on the Jamf Pro server:
#
# Jamf Pro Server Objects:
#
# Advanced Computer Searches: Read

# Set exit error status

ERROR=0

# If you choose to specify a directory to save the downloaded advanced computer searches into,
# please enter the complete directory path into the AdvancedComputerSearchDownloadDirectory
# variable below.

AdvancedComputerSearchDownloadDirectory=""

# If the AdvancedComputerSearchDownloadDirectory isn't specified above, a directory will be
# created and the complete directory path displayed by the script.

if [[ -z "$AdvancedComputerSearchDownloadDirectory" ]]; then
   AdvancedComputerSearchDownloadDirectory=$(mktemp -d)
   echo "A location to store downloaded advanced computer searches has not been specified."
   echo "Downloaded advanced computer searches will be stored in $AdvancedComputerSearchDownloadDirectory."
fi

# If you choose to hardcode API information into the script, set one or more of the following values:
#
# The username for an account on the Jamf Pro server with sufficient API privileges
# The password for the account
# The Jamf Pro URL

# Set the Jamf Pro URL here if you want it hardcoded.
jamfpro_url=""	    

# Set the username here if you want it hardcoded.
jamfpro_user=""

# Set the password here if you want it hardcoded.
jamfpro_password=""	

# If you do not want to hardcode API information into the script, you can also store
# these values in a ~/Library/Preferences/com.github.jamfpro-info.plist file.
#
# To create the file and set the values, run the following commands and substitute
# your own values where appropriate:
#
# To store the Jamf Pro URL in the plist file:
# defaults write com.github.jamfpro-info jamfpro_url https://jamf.pro.server.goes.here:port_number_goes_here
#
# To store the account username in the plist file:
# defaults write com.github.jamfpro-info jamfpro_user account_username_goes_here
#
# To store the account password in the plist file:
# defaults write com.github.jamfpro-info jamfpro_password account_password_goes_here
#
# If the com.github.jamfpro-info.plist file is available, the script will read in the
# relevant information from the plist file.

if [[ -f "$HOME/Library/Preferences/com.github.jamfpro-info.plist" ]]; then

  if [[ -z "$jamfpro_url" ]]; then
     jamfpro_url=$(defaults read $HOME/Library/Preferences/com.github.jamfpro-info jamfpro_url)
  fi     

  if [[ -z "$jamfpro_user" ]]; then
     jamfpro_user=$(defaults read $HOME/Library/Preferences/com.github.jamfpro-info jamfpro_user)
  fi
  
  if [[ -z "$jamfpro_password" ]]; then
     jamfpro_password=$(defaults read $HOME/Library/Preferences/com.github.jamfpro-info jamfpro_password)
  fi

fi

# If the Jamf Pro URL, the account username or the account password aren't available
# otherwise, you will be prompted to enter the requested URL or account credentials.

if [[ -z "$jamfpro_url" ]]; then
     read -p "Please enter your Jamf Pro server URL : " jamfpro_url
fi

if [[ -z "$jamfpro_user" ]]; then
     read -p "Please enter your Jamf Pro user account : " jamfpro_user
fi

if [[ -z "$jamfpro_password" ]]; then
     read -p "Please enter the password for the $jamfpro_user account: " -s jamfpro_password
fi

echo ""

# Remove the trailing slash from the Jamf Pro URL if needed.
jamfpro_url=${jamfpro_url%%/}

xpath() {
    # xpath in Big Sur changes syntax
    # For details, please see https://scriptingosx.com/2020/10/dealing-with-xpath-changes-in-big-sur/
    if [[ $(sw_vers -buildVersion) > "20A" ]]; then
        /usr/bin/xpath -e "$@"
    else
        /usr/bin/xpath "$@"
    fi
}

initializeAdvancedComputerSearchDownloadDirectory ()
{

if [[ -z "$AdvancedComputerSearchDownloadDirectory" ]]; then

   AdvancedComputerSearchDownloadDirectory=$(mktemp -d)
   echo "A location to store downloaded advanced computer searches has not been specified."
   echo "Downloaded advanced computer searches will be stored in $AdvancedComputerSearchDownloadDirectory."
   echo "$AdvancedComputerSearchDownloadDirectory not found.  Creating..."
   mkdir -p $AdvancedComputerSearchDownloadDirectory
   
   if [[ $? -eq 0 ]]; then
   		echo "Successfully created $AdvancedComputerSearchDownloadDirectory"
   	else
   		echo "Could not create $AdvancedComputerSearchDownloadDirectory"
   		echo "Please make sure the parent directory is writable. Exiting...."
   		ERROR=1
   	fi
   	
else

   # Remove the trailing slash from the AdvancedComputerSearchDownloadDirectory variable if needed.
   AdvancedComputerSearchDownloadDirectory=${AdvancedComputerSearchDownloadDirectory%%/}

   if [[ -d "$AdvancedComputerSearchDownloadDirectory" ]] && [[ -n "$(ls -A "$AdvancedComputerSearchDownloadDirectory")" ]]; then
		archive_file="AdvancedComputerSearchDownloadDirectoryArchive-`date +%Y%m%d%H%M%S`.zip"
		echo "Archiving previous advanced computer search download directory to ${AdvancedComputerSearchDownloadDirectory%/*}/$archive_file"
		ditto -ck "$AdvancedComputerSearchDownloadDirectory" "${AdvancedComputerSearchDownloadDirectory%/*}/$archive_file"
		
		if [[ $? -eq 0 ]]; then
				echo "Successfully created ${AdvancedComputerSearchDownloadDirectory%/*}/$archive_file"
				
				# Removing existing directory after archiving is complete.
				rm -rf $AdvancedComputerSearchDownloadDirectory
		
				# Creating a new directory with the same name.
				mkdir -p $AdvancedComputerSearchDownloadDirectory
				
				if [[ $? -eq 0 ]]; then
					echo "Successfully created new $AdvancedComputerSearchDownloadDirectory"
				else
					echo "Could not create new $AdvancedComputerSearchDownloadDirectory"
					echo "Please make sure the parent directory is writable. Exiting...."
					ERROR=1
				fi
			else
				echo "Could not create $archive_file. Exiting...."
				ERROR=1
		fi

		
   elif [[ -d "$AdvancedComputerSearchDownloadDirectory" ]] && [[ -z "$(ls -A "$AdvancedComputerSearchDownloadDirectory")" ]]; then
		echo  "$AdvancedComputerSearchDownloadDirectory exists but is empty. Using existing directory for downloading advanced computer searches."
   
   elif [[ -n "$AdvancedComputerSearchDownloadDirectory" ]] && [[ ! -d "$AdvancedComputerSearchDownloadDirectory" ]]; then
		echo  "$AdvancedComputerSearchDownloadDirectory does not exist. Creating $AdvancedComputerSearchDownloadDirectory for downloading advanced computer searches."
		mkdir -p $AdvancedComputerSearchDownloadDirectory
		
		if [[ $? -eq 0 ]]; then
			echo "Successfully created new $AdvancedComputerSearchDownloadDirectory"
		else
			echo "Could not create new $AdvancedComputerSearchDownloadDirectory"
			echo "Please make sure the parent directory is writable. Exiting...."
			ERROR=1
		fi
	fi

fi
}

DownloadAdvancedComputerSearch(){

	# Download the advanced computer search information as raw XML,
	# then format it to be readable.
	echo "Downloading advanced computer search with id $1..."
	FormattedAdvancedComputerSearch=$(curl -su "${jamfpro_user}:${jamfpro_password}" -H "Accept: application/xml" "${jamfpro_url}/JSSResource/advancedcomputersearches/id/$1" -X GET | tr $'\n' $'\t' | sed -E 's|<computers>.*</computers>||' |  tr $'\t' $'\n' | xmllint --format - )

	if [[ -n "$FormattedAdvancedComputerSearch" ]]; then
	
		# Identify and display the advanced computer search's name.
		DisplayName=$(echo "$FormattedAdvancedComputerSearch" | xpath "/advanced_computer_search/name/text()" 2>/dev/null | sed -e 's|:|(colon)|g' -e 's/\//\\/g')
		echo "Downloaded advanced computer search is named: $DisplayName"

		# Save the downloaded advanced computer search.

		echo "Saving ${DisplayName}.xml file to $AdvancedComputerSearchDownloadDirectory."
	
		if [[ -d "$AdvancedComputerSearchDownloadDirectory" ]]; then
		  echo "$FormattedAdvancedComputerSearch" > "$AdvancedComputerSearchDownloadDirectory/${DisplayName}.xml" 
		else
		  mkdir -p "$AdvancedComputerSearchDownloadDirectory/$PolicyCategory"
		  echo "$FormattedAdvancedComputerSearch" > "$AdvancedComputerSearchDownloadDirectory/${DisplayName}.xml"
		fi
		
	fi
}

# Back up existing advanced computer search downloads and create advanced computer search download directory.

initializeAdvancedComputerSearchDownloadDirectory

if [[ $ERROR -eq 0 ]]; then

	# Download latest version of all advanced computer searches. For performance reasons, we
	# parallelize the execution.
	MaximumConcurrentJobs=10
	ActiveJobs=0
	AdvancedComputerSearch_id_list=$(curl -su "${jamfpro_user}:${jamfpro_password}" -H "Accept: application/xml" "${jamfpro_url}/JSSResource/advancedcomputersearches" | xpath "//id" 2>/dev/null)
	AdvancedComputerSearch_id=$(echo "$AdvancedComputerSearch_id_list" | grep -Eo "[0-9]+")

	echo "Downloading advanced computer searches from $jamfpro_url..."
	
	for ID in ${AdvancedComputerSearch_id}; do

		((ActiveJobs=ActiveJobs%MaximumConcurrentJobs)); ((ActiveJobs++==0)) && wait
   		DownloadAdvancedComputerSearch "$ID" &
   		
	done	
fi

exit $ERROR