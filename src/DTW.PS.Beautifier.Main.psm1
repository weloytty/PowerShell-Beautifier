﻿<#
PowerShell script beautifier by Dan Ward.

IMPORTANT NOTE: this utility rewrites your script in place!  Before running this
on your script make sure you back up your script or commit any changes you have 
or run this on a copy of your script.

This file contains the main function (Edit-DTWBeautifyScript, at end of this file)
along with a number of key functions.  Read the help on Edit-DTWBeautifyScript or
load the module and run:
Get-Help Edit-DTWBeautifyScript -Full

See https://github.com/DTW-DanWard/PowerShell-Beautifier or http://dtwconsulting.com 
for more information.  I hope you enjoy using this utility!
-Dan Ward
#>


Set-StrictMode -Version 2

#region Function: Initialize-ProcessVariables

<#
.SYNOPSIS
Initialize the module-level variables used in processing a file.
.DESCRIPTION
Initialize the module-level variables used in processing a file.
#>
function Initialize-ProcessVariables {
  #region Function parameters
  [CmdletBinding()]
  param()
  #endregion
  process {
    # keep track if everything initialized correctly before allowing script to run,
    # most notably to make sure required modules are loaded; set to true at end of
    # initialize and checked at beginning of main function
    [bool]$script:ModuleInitialized = $false

    # make sure required functions are loaded
    # Get-DTWFileEncoding is required for get encoding function
    [string]$RequiredFunctionName = 'Get-DTWFileEncoding'
    $RequiredFunction = Get-Command -Name $RequiredFunctionName -ErrorAction SilentlyContinue
    if ($null -eq $RequiredFunction) {
      Write-Error -Message "Required function $RequiredFunctionName is not loaded; cannot process files."
      return
    }

    #region Initialize process variables
    # indent text; use two spaces by default, value is overridden with param
    [string]$script:IndentText = '  '

    # initialize file path information
    # source file to process
    [string]$script:SourcePath = $null
    # destination file; this value is different from SourcePath if Edit-DTWBeautifyScript -DestinationPath is specified
    [string]$script:DestinationPath = $null
    # result content is created in a temp file; if no errors this becomes the result file
    [string]$script:DestinationPathTemp = $null

    # initialize source script storage
    [string]$script:SourceScriptString = $null
    [System.Text.Encoding]$script:SourceFileEncoding = $null
    [System.Management.Automation.PSToken[]]$script:SourceTokens = $null

    # initialize destination storage
    [System.IO.StreamWriter]$script:DestinationStreamWriter = $null
    #endregion

    # if got this far, everything is good
    $script:ModuleInitialized = $true
  }
}
#endregion

#region Look up value in valid name lookup tables

#region Function: Get-ValidCommandName

<#
.SYNOPSIS
Retrieves command name with correct casing, expands aliases
.DESCRIPTION
Retrieves the 'proper' command name for aliases, cmdlets and functions.  When
called with an alias, the corresponding command name is returned.  When called
with a command name, the name of the command as defined in memory (and stored 
in the lookup table) is returned, which should have the correct case.  
If Name is not found in the ValidCommandNames lookup table, it is added and 
returned as-is.  That means the first instance of the command name that is 
encountered becomes the correct version, using its casing as the clean version.
.PARAMETER Name
The name of the cmdlet, function or alias
.EXAMPLE
Get-ValidCommandName -Name dir
Returns: Get-ChildItem
.EXAMPLE
Get-ValidCommandName -Name GET-childitem
Returns: Get-ChildItem
.EXAMPLE
Get-ValidCommandName -Name FunNotFound; Get-ValidCommandName -Name funNOTfound
Returns: FunNotFound, FunNotFound
#>
function Get-ValidCommandName {
  #region Function parameters
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [string]$Name
  )
  #endregion
  process {
    # look up name in lookup table and return
    # if not found (new function added within script), add to list and return
    if ($MyInvocation.MyCommand.Module.PrivateData['ValidCommandNames'].ContainsKey($Name)) {
      $MyInvocation.MyCommand.Module.PrivateData['ValidCommandNames'].Item($Name)
    } else {
      $MyInvocation.MyCommand.Module.PrivateData['ValidCommandNames'].Add($Name,$Name) > $null
      $Name
    }
  }
}
#endregion

#region Function: Get-ValidCommandParameterName

<#
.SYNOPSIS
Retrieves command parameter name with correct casing
.DESCRIPTION
Retrieves the proper command parameter name using the command parameter 
names currently found in memory (and stored in the lookup table).
If Name is not found in the ValidCommandParameterNames lookup table, it is
added and returned as-is.  That means the first instance of the command 
parameter name that is encountered becomes the correct version, using its 
casing as the clean version.

NOTE: parameter names are expected to be prefixed with a -
.PARAMETER Name
The name of the command parameter
.EXAMPLE
Get-ValidCommandParameterName -Name "-path"
Returns: -Path
.EXAMPLE
Get-ValidCommandParameterName -Name "-RECURSE"
Returns: -Recurse
.EXAMPLE
Get-ValidCommandParameterName -Name "-ParamNotFound"; Get-ValidCommandParameterName -Name "-paramNOTfound"
Returns: -ParamNotFound, -ParamNotFound
#>
function Get-ValidCommandParameterName {
  #region Function parameters
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [string]$Name
  )
  #endregion
  process {
    # look up name in lookup table and return
    # if not found (new function added within script), add to list and return
    if ($MyInvocation.MyCommand.Module.PrivateData['ValidCommandParameterNames'].ContainsKey($Name)) {
      $MyInvocation.MyCommand.Module.PrivateData['ValidCommandParameterNames'].Item($Name)
    } else {
      $MyInvocation.MyCommand.Module.PrivateData['ValidCommandParameterNames'].Add($Name,$Name) > $null
      $Name
    }
  }
}
#endregion

#region Function: Get-ValidAttributeName

<#
.SYNOPSIS
Retrieves attribute name with correct casing
.DESCRIPTION
Retrieves the proper attribute name using the parameter attribute values
stored in the lookup table.
If Name is not found in the ValidAttributeNames lookup table, it is
added and returned as-is.  That means the first instance of the attribute 
that is encountered becomes the correct version, using its casing as the 
clean version.
.PARAMETER Name
The name of the attribute
.EXAMPLE
Get-ValidAttributeName -Name validatenotnull
Returns: ValidateNotNull
.EXAMPLE
Get-ValidAttributeName -Name AttribNotFound; Get-ValidAttributeName -Name ATTRIBNotFound
Returns: AttribNotFound, AttribNotFound
#>
function Get-ValidAttributeName {
  #region Function parameters
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [string]$Name
  )
  #endregion
  process {
    # look up name in lookup table and return
    # if not found, add to list and return
    if ($MyInvocation.MyCommand.Module.PrivateData['ValidAttributeNames'].ContainsKey($Name)) {
      $MyInvocation.MyCommand.Module.PrivateData['ValidAttributeNames'].Item($Name)
    } else {
      $MyInvocation.MyCommand.Module.PrivateData['ValidAttributeNames'].Add($Name,$Name) > $null
      $Name
    }
  }
}
#endregion

#region Function: Get-ValidMemberName

<#
.SYNOPSIS
Retrieves member name with correct casing
.DESCRIPTION
Retrieves the proper member name using the member values stored in the lookup table.
If Name is not found in the ValidMemberNames lookup table, it is
added and returned as-is.  That means the first instance of the member 
that is encountered becomes the correct version, using its casing as the 
clean version.
.PARAMETER Name
The name of the member
.EXAMPLE
Get-ValidMemberName -Name valuefrompipeline
Returns: ValueFromPipeline
.EXAMPLE
Get-ValidMemberName -Name tostring
Returns: ToString
.EXAMPLE
Get-ValidMemberName -Name MemberNotFound; Get-ValidMemberName -Name MEMBERnotFound
Returns: MemberNotFound, MemberNotFound
#>
function Get-ValidMemberName {
  #region Function parameters
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [string]$Name
  )
  #endregion
  process {
    # look up name in lookup table and return
    # if not found, add to list and return
    if ($MyInvocation.MyCommand.Module.PrivateData['ValidMemberNames'].ContainsKey($Name)) {
      $MyInvocation.MyCommand.Module.PrivateData['ValidMemberNames'].Item($Name)
    } else {
      $MyInvocation.MyCommand.Module.PrivateData['ValidMemberNames'].Add($Name,$Name) > $null
      $Name
    }
  }
}
#endregion

#region Function: Get-ValidVariableName

<#
.SYNOPSIS
Retrieves variable name with correct casing
.DESCRIPTION
Retrieves the proper variable name using the variable name values stored in the 
lookup table. If Name is not found in the ValidVariableNames lookup table, it is
added and returned as-is.  That means the first instance of the variable 
that is encountered becomes the correct version, using its casing as the 
clean version.
.PARAMETER Name
The name of the member
.EXAMPLE
Get-ValidVariableName -Name TRUE
Returns: true
.EXAMPLE
Get-ValidVariableName -Name MyVar; Get-ValidVariableName -Name MYVAR
Returns: MyVar, MyVar
#>
function Get-ValidVariableNameL {
  #region Function parameters
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [string]$Name
  )
  #endregion
  process {
    # look up name in lookup table and return
    # if not found, add to list and return
    if ($MyInvocation.MyCommand.Module.PrivateData['ValidVariableNames'].ContainsKey($Name)) {
      $MyInvocation.MyCommand.Module.PrivateData['ValidVariableNames'].Item($Name)
    } else {
      $MyInvocation.MyCommand.Module.PrivateData['ValidVariableNames'].Add($Name,$Name) > $null
      $Name
    }
  }
}
#endregion

#endregion

#region Add content to DestinationFileStreamWriter

<#
.SYNOPSIS
Copies a string into the destination stream.
.DESCRIPTION
Copies a string into the destination stream.
.PARAMETER Text
String to copy into destination stream.
#>
function Add-StringContentToDestinationFileStreamWriter {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [string]$Text
  )
  process {
    $script:DestinationStreamWriter.Write($Text)
  }
}

<#
.SYNOPSIS
Copies a section from the source string array into the destination stream.
.DESCRIPTION
Copies a section from the source string array into the destination stream.
.PARAMETER StartSourceIndex
Index in source string to start copy
.PARAMETER StartSourceLength
Length to copy
#>
function Copy-ArrayContentFromSourceArrayToDestinationFileStreamWriter {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [int]$StartSourceIndex,
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [int]$StartSourceLength
  )
  process {
    for ($i = $StartSourceIndex; $i -lt ($StartSourceIndex + $StartSourceLength); $i++) {
      $script:DestinationStreamWriter.Write($SourceScriptString[$i])
    }
  }
}
#endregion

#region Load content functions

<#
.SYNOPSIS
Reads content from source script into memory
.DESCRIPTION
Reads content from source script into memory
#>
function Import-ScriptContent {
  #region Function parameters
  [CmdletBinding()]
  param()
  #endregion
  process {
    # get the file encoding of the file; it will be a type defined at System.Text.Encoding
    [System.Text.Encoding]$script:SourceFileEncoding = Get-DTWFileEncoding -Path $DestinationPathTemp
    # paths have already been validated so no testing of paths here
    # load file as a single String, needs to be single string for correct usage of
    # Tokenize method BUT we also need access to the original characters by byte so we can copy string values
    $script:SourceScriptString = [System.IO.File]::ReadAllText($DestinationPathTemp)
    if ($? -eq $false) {
      Write-Error -Message "Error occurred reading all text for getting content for SourceScriptString with file: $DestinationPathTemp"
      return
    }
  }
}
#endregion

#region Tokenize source script content

<#
.SYNOPSIS
Tokenizes code stored in $SourceScriptString, stores in $SourceTokens
.DESCRIPTION
Tokenizes code stored in $SourceScriptString, stores in $SourceTokens.  If an error
occurs, the error objects are written to the error stream.
#>
function Invoke-TokenizeSourceScriptContent {
  #region Function parameters
  [CmdletBinding()]
  param()
  #endregion
  process {
    $Err = $null
    #region We HAVE to use the Tokenize method that takes a single string 
    <#
      Fun note: we **HAVE** to use the Tokenize method signature that uses the single string as opposed to
      the one that takes an object array (like you might use with Get-Content)!!!  The reason is low-level
      and not pretty: if your source code has line endings that are just ASCII 10 Line Feed (as opposed to
      Windows standard 13 10 CR LF), the Tokenize method will introduce an error into the Token details.
      Specifically, between using Get-Content and passing the array of strings into Tokenize, the single 
      10 will be converted/confused with 13 10, the Start value locations for tokens following NewLines will
      be incremented by 1 but this won't jive with our $SourceScriptString which is the original file in bytes.
    #>
    #endregion
    $script:SourceTokens = [System.Management.Automation.PSParser]::Tokenize($SourceScriptString,[ref]$Err)
    if ($null -ne $Err -and $Err.Count) {
      Write-Error -Message 'An error occurred; is there invalid PowerShell or some formatting / syntax issue in the script? See error record below.'
      $Err | ForEach-Object {
        Write-Error -Message "$($_.Message) Content: $($_.Token.Content), line: $($_.Token.StartLine), column: $($_.Token.StartColumn)"
      }
      return
    }
  }
}
#endregion

#region Function to create destination file stream/writer

<#
.SYNOPSIS
Migrates content to destination stream.
.DESCRIPTION
Walks through tokens and for each copies (possibly modified) content to
destination stream.
#>
function Copy-SourceContentToDestinationStream {
  #region Function parameters
  [CmdletBinding()]
  param()
  #endregion
  process {
    [int]$CurrentIndent = 0
    for ($i = 0; $i -lt $SourceTokens.Count; $i++) {
      # remove indents before writing GroupEnd
      if ($SourceTokens[$i].Type -eq 'GroupEnd') { $CurrentIndent -= 1 }

      #region Add indent to beginning of line
      # if last character was a NewLine or LineContinuation and current one isn't 
      # a NewLine nor a groupend, add indent prefix
      if ($i -gt 0 -and ($SourceTokens[$i - 1].Type -eq 'NewLine' -or $SourceTokens[$i - 1].Type -eq 'LineContinuation') `
           -and $SourceTokens[$i].Type -ne 'NewLine') {

        [int]$IndentToUse = $CurrentIndent
        # if last token was a LineContinuation, add an extra (one-time) indent
        # so indent lines continued (say cmdlet with many params)
        if ($SourceTokens[$i - 1].Type -eq 'LineContinuation') { $IndentToUse += 1 }
        # add the space prefix
        if ($IndentToUse -gt 0) {
          Add-StringContentToDestinationFileStreamWriter ($IndentText * $IndentToUse)
        }
      }
      #endregion

      # write the content of the token to the destination stream
      Write-TokenContentByType -SourceTokenIndex $i

      #region Add space after writing token
      if ($true -eq (Test-AddSpaceFollowingToken -TokenIndex $i)) {
        Add-StringContentToDestinationFileStreamWriter ' '
      }
      #endregion

      #region Add indents after writing GroupStart
      if ($SourceTokens[$i].Type -eq 'GroupStart') { $CurrentIndent += 1 }
      #endregion
    }
  }
}
#endregion

#region Get new token functions

#region Function: Write-TokenContentByType

<#
.SYNOPSIS
Calls a token-type-specific function to writes token to destination stream.
.DESCRIPTION
This function calls a token-type-specific function to write the token's content
to the destination stream.  Based on the varied details about cleaning up 
the code based on type, expanding aliases, etc., this is best done in a function
for each type.  Even though many of these functions are similar (just 'write' 
content) to stream, let's keep these separate for easier maintenance.
The token's .Type is checked and the corresponding function Write-TokenContent_<type>
is called, which writes the token's content appropriately to the destination stream. 
There is a Write-TokenContent_* method for each entry on 
System.Management.Automation.PSTokenType
http://msdn.microsoft.com/en-us/library/system.management.automation.pstokentype(v=VS.85).aspx
.PARAMETER SourceTokenIndex
Index of current token in SourceTokens
#>
function Write-TokenContentByType {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [int]$SourceTokenIndex
  )
  process {
    # get name of function to call, based on type of source token
    [string]$FunctionName = 'Write-TokenContent_' + $SourceTokens[$SourceTokenIndex].Type
    # call the appropriate new Token function, passing in source token, and return result
    & $FunctionName $SourceTokens[$i]
  }
}
#endregion

#region Write-TokenContent_* functions description
<#
Ok, normally I'd have help sections defined for each of these functions but they are
all incredibly similar and all that help is really just bloat.  (This file is getting 
bigger and bigger!).  Plus, these functions are private - not exported, so they will
never be accessed directly via Get-Help.

There are three important points to know about the Write-TokenContent_* functions:

1. There is a Write-TokenContent_* method for each Token.Type, that is, for each property 
value on the System.Management.Automation.PSTokenType enum.
See: http://msdn.microsoft.com/en-us/library/system.management.automation.pstokentype(v=VS.85).aspx

2. Each function writes the content to the destination stream using one of two ways:
  Add-StringContentToDestinationFileStreamWriter <string> 
    adds <string> to destination stream
  Copy-ArrayContentFromSourceArrayToDestinationFileStream
    copies the content directly from the source array to the destination stream
    
Why does the second function copy directly from the source array to the destination 
stream?  It has everything to do with escaped characters and whitespace issues.
Let's say your code has this line: Write-Host "Hello`tworld"
The problem is that if you store that "Hello`tworld" as a string, it becomes "Hello    world"
So, if you use the Token.Content value (whose value is a string), you have the expanded
string with the spaces.  This is fine if you are running the command and outputting the
results - they would be the same.  But if you are re-writing the source code, it's a
big problem.  By looking at the string "Hello    world" you don't know if that was its
original value or if "Hello`tworld" was.  You can easily re-escape the whitespace characters
within a string ("aa`tbb" -replace "`t","``t"), but you still don't know what the 
original was. I don't want to change your code incorrectly, I want it to be exactly the 
way that it was written before, just with correct whitespace, expanded aliases, etc. 
so storing the results in a stream is the way to go.  And as for the second function
Copy-ArrayContentFromSourceArrayToDestinationFileStream, copying each element from
the source array to the destination stream is the only way to keep the whitespace
intact.  If we extracted the content from the array into a string then wrote that to
the destination stream, we'd be back at square one.

This is important for these Token types: CommandArguments, String and Variable.
String is obvious.  Variable names can have whitespace using the { } notation; 
this is a perfectly valid, if insane, statement:  ${A`nB} = "hey now"
The Variable is named A`nB.
CommandArguments can also have whitespace AND will not have surrounding quotes.
For example, if this is tokenized: dir "c:\Program Files"
The "c:\Program Files" is tokenized as a String.  
However, the statement could be written as: dir c:\Program` Files
In this case, "c:\Program` Files" (no quotes!) is tokenized as a CommandArgument
that has whitespace in its value.  Joy.

3. Some functions will alter the value of the Token.Content before storing in the 
destination stream.  This is when the aliases are expanded, casing is fixed for 
command/parameter names, casing is fixed for types, keywords, etc.

Any special details will be described in each function.
#>
#endregion

#region Write token content for: Attribute
function Write-TokenContent_Attribute {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # check/replace Attribute value in ValidAttributeNames lookup table
    Add-StringContentToDestinationFileStreamWriter (Get-ValidAttributeName -Name $Token.Content)
  }
}
#endregion

#region Write token content for: Command
function Write-TokenContent_Command {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # check/replace CommandValue value in ValidCommandNames lookup table
    Add-StringContentToDestinationFileStreamWriter (Get-ValidCommandName -Name $Token.Content)
  }
}
#endregion

#region Write token content for: CommandArgument
function Write-TokenContent_CommandArgument {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # If you are creating a proxy function (function with same name as existing Cmdlet), it will be 
    # tokenized as a CommandArgument.  So, let's make sure the casing is the same by doing a lookup.
    # If the value is found in the valid list of CommandNames, it does not contain whitespace, so 
    # it should be safe to do a lookup and add the replacement text to the destination stream
    # otherwise copy the command argument text from source to destination.
    if ($MyInvocation.MyCommand.Module.PrivateData['ValidCommandNames'].ContainsKey($Token.Content)) {
      Add-StringContentToDestinationFileStreamWriter (Get-ValidCommandName -Name $Token.Content)
    } else {
      # CommandArgument values can have whitespace, thanks to the escaped characters, i.e. dir c:\program` files
      # so we need to copy the value directly from the source to the destination stream.
      # By copying from the Token.Start with a length of Token.Length, we will also copy the 
      # backtick characters correctly
      Copy-ArrayContentFromSourceArrayToDestinationFileStreamWriter -StartSourceIndex $Token.Start -StartSourceLength $Token.Length
    }
  }
}
#endregion

#region Write token content for: CommandParameter
function Write-TokenContent_CommandParameter {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # check/replace CommandParameterName value in ValidCommandParameterNames lookup table
    Add-StringContentToDestinationFileStreamWriter (Get-ValidCommandParameterName -Name $Token.Content)
  }
}
#endregion

#region Write token content for: Comment
function Write-TokenContent_Comment {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # add Comment Content as-is to destination
    Add-StringContentToDestinationFileStreamWriter $Token.Content
  }
}
#endregion

#region Write token content for: GroupEnd
function Write-TokenContent_GroupEnd {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # add GroupEnd Content as-is to destination
    Add-StringContentToDestinationFileStreamWriter $Token.Content
  }
}
#endregion

#region Write token content for: GroupStart
function Write-TokenContent_GroupStart {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # add GroupStart Content as-is to destination
    Add-StringContentToDestinationFileStreamWriter $Token.Content
  }
}
#endregion

#region Write token content for: KeyWord
function Write-TokenContent_KeyWord {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # add KeyWord Content with lower case to destination
    Add-StringContentToDestinationFileStreamWriter $Token.Content.ToLower()
  }
}
#endregion

#region Write token content for: LoopLabel
function Write-TokenContent_LoopLabel {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # When tokenized, the loop label definition has a token type LoopLabel
    # and its content includes the colon prefix. However, when that loop label 
    # is used in a break statement, though, the loop label name is tokenized 
    # as a Member. So, in this function where the LoopLabel is defined, grab
    # the name (without the colon) and lookup (add if not found) to the 
    # Member lookup table.  When the loop label is used in the break statement,
    # it will look up in the Member table and use the same value, so the case
    # will be the same.

    # so, look up LoopLable name without colon in Members
    [string]$LookupNameInMembersNoColon = Get-ValidMemberName -Name ($Token.Content.Substring(1))
    # add to destination using lookup value but re-add colon prefix
    Add-StringContentToDestinationFileStreamWriter (':' + $LookupNameInMembersNoColon)
  }
}
#endregion

#region Write token content for: LineContinuation
function Write-TokenContent_LineContinuation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # add LineContinuation Content as-is to destination
    Add-StringContentToDestinationFileStreamWriter $Token.Content
  }
}
#endregion

#region Write token content for: Member
function Write-TokenContent_Member {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # check/replace Member value in ValidMemberNames lookup table
    Add-StringContentToDestinationFileStreamWriter (Get-ValidMemberName -Name $Token.Content)
  }
}
#endregion

#region Write token content for: NewLine
function Write-TokenContent_NewLine {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # add NewLine using Windows standard to destination
    Add-StringContentToDestinationFileStreamWriter "`r`n"
  }
}
#endregion

#region Write token content for: Number
function Write-TokenContent_Number {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # add Number Content as-is to destination
    Add-StringContentToDestinationFileStreamWriter $Token.Content
  }
}
#endregion

#region Write token content for: Operator
function Write-TokenContent_Operator {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # add Operator Content with lower case to destination
    Add-StringContentToDestinationFileStreamWriter $Token.Content.ToLower()
  }
}
#endregion

#region Write token content for: Position
# I can't find much help info online about this type!  Just replicate content
function Write-TokenContent_Position {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    Add-StringContentToDestinationFileStreamWriter $Token.Content
  }
}
#endregion

#region Write token content for: StatementSeparator
function Write-TokenContent_StatementSeparator {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # add StatementSeparator Content as-is to destination
    Add-StringContentToDestinationFileStreamWriter $Token.Content
  }
}
#endregion

#region Write token content for: String
function Write-TokenContent_String {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # String values can have whitespace, thanks to the escaped characters, i.e. "Hello`tworld"
    # so we need to copy the value directly from the source to the destination stream.
    # By copying from the Token.Start with a length of Token.Length, we will also copy the 
    # correct string boundary quote characters - even if it's a here-string. Nice!
    # Also, did you know that PowerShell supports multi-line strings that aren't here-strings?
    # This is valid:
    # $Message = "Hello
    # world"
    # It works.  I wish it didn't.
    Copy-ArrayContentFromSourceArrayToDestinationFileStreamWriter -StartSourceIndex $Token.Start -StartSourceLength $Token.Length
  }
}
#endregion

#region Write token content for: Type
function Write-TokenContent_Type {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # first, get the type name
    [string]$TypeName = $Token.Content
    # next, remove any brackets found in the type name (some versions PowerShell include, some don't)
    if (($TypeName[0] -eq '[') -and ($TypeName[-1] -eq ']')) {
      $TypeName = $TypeName.Substring(1,$TypeName.Length - 2)
    }

    # OK, now let's try to get the correct case for the type
    # first, if it's a built-in PowerShell shortcut type like [int] or [string] then
    # i.e. there's no . character in the type name, in which case, just lowercase it
    if ($TypeName.IndexOf('.') -eq -1) {
      $TypeName = $TypeName.ToLower()
    } else {
      # else there is a . character in the type, so let's try to create the type and then get the 
      # fullname from the type itself.  But if that fails (module/assembly not loaded) then just 
      # use the original type name value from the script.

      # need to wrap in try/catch in case type isn't loaded into memory
      # if works, re-add surrounding brackets
      # if doesn't, take $TypeName and re-add brackets
      try { $TypeName = ([type]::GetType($TypeName,$true,$true)).FullName }
      catch { $TypeName = $TypeName }
    }
    # finally re-add [ ] around type name for writing back
    $TypeName = '[' + $TypeName + ']'
    Add-StringContentToDestinationFileStreamWriter $TypeName
  }
}
#endregion

#region Write token content for: Variable
function Write-TokenContent_Variable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # Variable names can have whitespace, thanks to the ${ } notation, i.e. ${A`nB} = 123
    # so we need to copy the value directly from the source to the destination stream.
    # By copying from the Token.Start with a length of Token.Length, we will also copy the 
    # variable markup, that is the $ or ${ }
    Copy-ArrayContentFromSourceArrayToDestinationFileStreamWriter -StartSourceIndex $Token.Start -StartSourceLength $Token.Length
  }
}
#endregion

#region Write token content for: Unknown
# I can't find much help info online about this type!  Just replicate content
function Write-TokenContent_Unknown {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $false)]
    [System.Management.Automation.PSToken]$Token
  )
  process {
    # add Unknown Content as-is to destination
    Add-StringContentToDestinationFileStreamWriter $Token.Content
  }
}
#endregion

#endregion

#region Function: Test-AddSpaceFollowingToken

<#
.SYNOPSIS
Returns $true if current token should be followed by a space, $false otherwise.
.DESCRIPTION
Returns $true if the current token, identified by the TokenIndex parameter, should
be followed by a space.  The logic that follows is basic: if a rule is found that 
determines a space should not be added $false is returned immediately.  If all rules
pass, $true is returned.  I normally do not like returning from within a function
in PowerShell but this logic is clean, the rules are well organized and it shaves some 
time off the process.
Here's an example: we don't want spaces between the [] characters for array index;
we want $MyArray[5], not $MyArray[ 5 ]. 
The rules will typically look at the current token BUT may want to check the next token 
as well.
.PARAMETER TokenIndex
Index of current token in $SourceTokens
#>
function Test-AddSpaceFollowingToken {
  #region Function parameters
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false,ValueFromPipeline = $false)]
    [int]$TokenIndex
  )
  #endregion
  process {
    # Notes: we sometimes need to check the next token to determine if we need to add a space.
    # In those checks, we need to make sure the current token isn't the last.

    # If a rule is found that space shouldn't be added, immediately return false.  If makes it
    # all the way through rules, return true.  To speed up this functioning, the rules that are
    # most likely to be useful are at the top.

    #region Don't write space after type NewLine
    if ($SourceTokens[$TokenIndex].Type -eq 'NewLine') { return $false }
    #endregion

    #region Don't write space after type Type if followed by GroupStart, Number, String, Type or Variable (for example [int]$Age or [int]"5")
    # don't write at space after, for example [int]
    if ((($TokenIndex + 1) -lt $SourceTokens.Count) -and $SourceTokens[$TokenIndex].Type -eq 'Type' -and ('GroupStart','Number','String','Type','Variable') -contains $SourceTokens[$TokenIndex + 1].Type) { return $false }
    #endregion

    #region Don't write space if next token is StatementSeparator (;) or NewLine
    if (($TokenIndex + 1) -lt $SourceTokens.Count) {
      if ($SourceTokens[$TokenIndex + 1].Type -eq 'NewLine') { return $false }
      if ($SourceTokens[$TokenIndex + 1].Type -eq 'StatementSeparator') { return $false }
    }
    #endregion

    #region Don't add space before or after Operator [ or before Operator ]
    if ($SourceTokens[$TokenIndex].Type -eq 'Operator' -and $SourceTokens[$TokenIndex].Content -eq '[') { return $false }
    if ((($TokenIndex + 1) -lt $SourceTokens.Count) -and $SourceTokens[$TokenIndex + 1].Type -eq 'Operator' -and ($SourceTokens[$TokenIndex + 1].Content -eq '[' -or $SourceTokens[$TokenIndex + 1].Content -eq ']')) { return $false }
    #endregion

    #region Don't write spaces before or after these Operators: . .. ::
    if ((($TokenIndex + 1) -lt $SourceTokens.Count) -and $SourceTokens[$TokenIndex + 1].Type -eq 'Operator' -and $SourceTokens[$TokenIndex + 1].Content -eq '.') { return $false }
    if ($SourceTokens[$TokenIndex].Type -eq 'Operator' -and $SourceTokens[$TokenIndex].Content -eq '.') { return $false }

    if ((($TokenIndex + 1) -lt $SourceTokens.Count) -and $SourceTokens[$TokenIndex + 1].Type -eq 'Operator' -and $SourceTokens[$TokenIndex + 1].Content -eq '..') { return $false }
    if ($SourceTokens[$TokenIndex].Type -eq 'Operator' -and $SourceTokens[$TokenIndex].Content -eq '..') { return $false }

    if ((($TokenIndex + 1) -lt $SourceTokens.Count) -and $SourceTokens[$TokenIndex + 1].Type -eq 'Operator' -and $SourceTokens[$TokenIndex + 1].Content -eq '::') { return $false }
    if ($SourceTokens[$TokenIndex].Type -eq 'Operator' -and $SourceTokens[$TokenIndex].Content -eq '::') { return $false }
    #endregion

    #region Don't write space inside ( ) or $( ) groups
    if ($SourceTokens[$TokenIndex].Type -eq 'GroupStart' -and ($SourceTokens[$TokenIndex].Content -eq '(' -or $SourceTokens[$TokenIndex].Content -eq '$(')) { return $false }
    if ((($TokenIndex + 1) -lt $SourceTokens.Count) -and $SourceTokens[$TokenIndex + 1].Type -eq 'GroupEnd' -and $SourceTokens[$TokenIndex + 1].Content -eq ')') { return $false }
    #endregion

    #region Don't write space if GroupStart ( { @{ followed by GroupEnd or NewLine
    if ($SourceTokens[$TokenIndex].Type -eq 'GroupStart' -and ($SourceTokens[$TokenIndex + 1].Type -eq 'GroupEnd' -or $SourceTokens[$TokenIndex + 1].Type -eq 'NewLine')) { return $false }
    #endregion

    #region Don't write space if writing Member or Attribute and next token is GroupStart
    if ((($TokenIndex + 1) -lt $SourceTokens.Count) -and 'Member','Attribute' -contains $SourceTokens[$TokenIndex].Type -and $SourceTokens[$TokenIndex + 1].Type -eq 'GroupStart') { return $false }
    #endregion

    #region Don't write space if writing Variable and next Operator token is [ (for example: $MyArray[3])
    if ((($TokenIndex + 1) -lt $SourceTokens.Count) -and $SourceTokens[$TokenIndex].Type -eq 'Variable' -and $SourceTokens[$TokenIndex + 1].Type -eq 'Operator' -and $SourceTokens[$TokenIndex + 1].Content -eq '[') { return $false }
    #endregion

    #region Don't add space after Operators: , !
    if ($SourceTokens[$TokenIndex].Type -eq 'Operator' -and ($SourceTokens[$TokenIndex].Content -eq ',' -or $SourceTokens[$TokenIndex].Content -eq '!')) { return $false }
    #endregion

    #region Don't add space if next Operator token is: , ++ ;
    if ((($TokenIndex + 1) -lt $SourceTokens.Count) -and $SourceTokens[$TokenIndex + 1].Type -eq 'Operator' -and
      ',','++',';' -contains $SourceTokens[$TokenIndex + 1].Content) { return $false }
    #endregion

    #region Don't add space after Operator > as in: 2>$null or 2>&1
    if ((($TokenIndex + 1) -lt $SourceTokens.Count) -and $SourceTokens[$TokenIndex].Type -eq 'Operator' -and $SourceTokens[$TokenIndex].Content -eq '2>' -and
      $SourceTokens[$TokenIndex + 1].Type -eq 'Variable' -and $SourceTokens[$TokenIndex + 1].Content -eq 'null') { return $false }
    if ($SourceTokens[$TokenIndex].Type -eq 'Operator' -and $SourceTokens[$TokenIndex].Content -eq '2>&1') { return $false }
    #endregion

    #region Don't add space after Keyword param
    if ($SourceTokens[$TokenIndex].Type -eq 'Keyword' -and $SourceTokens[$TokenIndex].Content -eq 'param') { return $false }
    #endregion

    #region Don't add space after CommandParameters with :<variable>
    # This is for switch params that are programmatically specified with a variable, such as:
    #   dir -Recurse:$CheckSubFolders
    if ($SourceTokens[$TokenIndex].Type -eq 'CommandParameter' -and $SourceTokens[$TokenIndex].Content[-1] -eq ':') { return $false }
    #endregion

    # return $true indicating add a space
    return $true
  }
}
#endregion

#region Function: Edit-DTWBeautifyScript

<#
.SYNOPSIS
Cleans PowerShell script: re-indents code with spaces or tabs, cleans
and rearranges all whitespace within a line, replaces aliases with 
cmdlet names, replaces parameter names with proper casing, fixes case for 
[types], etc.
.DESCRIPTION
Cleans PowerShell script: re-indents code with spaces or tabs, cleans
and rearranges all whitespace within a line, replaces aliases with 
commands, replaces parameter names with proper casing, fixes case for 
[types], etc.

More specifically it:
 - properly indents code inside {}, [], () and $() groups
 - replaces aliases with the command names (dir -> Get-ChildItem)
 - fixes command name casing (get-childitem -> Get-ChildItem)
 - fixes parameter name casing (Test-Path -path -> Test-Path -Path)
 - fixes [type] casing
     changes all PowerShell shortcuts to lower ([STRING] -> [string])
     changes other types ([system.exception] -> [System.Exception]
       only works for types loaded into memory
 - cleans/rearranges all whitespace within a line
     many rules - see Test-AddSpaceFollowingToken to tweak


----------

IMPORTANT NOTE: this utility rewrites your script in place!  Before running this
on your script make sure you back up your script or commit any changes you have 
or run this on a copy of your script.

----------

When loading, the module caches all the commands, aliases, etc. in memory 
at the time.  If you've added new commands to memory since loading the 
module, you may want to reload it.


This utility doesn't do everything - it's version 1.  
Version 2 (using PowerShell tokenizing/AST functionality) should
allow me to update the parsing functionality. But just so you know, 
here's what it doesn't do:
 - change location of group openings, say ( or {, from same line to new
   line and vice-versa;
 - expand param names (Test-Path -Inc -> Test-Path -Include).

See https://github.com/DTW-DanWard/PowerShell-Beautifier or http://dtwconsulting.com 
for more information.  I hope you enjoy using this utility!
-Dan Ward


.PARAMETER SourcePath
Path to the source PowerShell file
.PARAMETER DestinationPath
Path to write reformatted PowerShell.  If not specified rewrites file
in place.
.PARAMETER Quiet
If specified, does not output status text.
.EXAMPLE
Edit-DTWBeautifyScript -Source c:\P\S1.ps1 -Destination c:\P\S1_New.ps1
Gets content from c:\P\S1.ps1, cleans and writes to c:\P\S1_New.ps1
.EXAMPLE
Edit-DTWBeautifyScript -SourcePath c:\P\S1.ps1
Writes cleaned script results back into c:\P\S1.ps1
.EXAMPLE
dir c:\CodeFiles -Include *.ps1,*.psm1 -Recurse | Edit-DTWBeautifyScript
For each .ps1 and .psm1 file, cleans and rewrites back into same file
#>
function Edit-DTWBeautifyScript {
  #region Function parameters
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,ValueFromPipeline = $true,ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [Alias('FullName')]
    [string]$SourcePath,
    [Parameter(Mandatory = $false,ValueFromPipeline = $false)]
    [string]$DestinationPath,
    [Parameter(Mandatory = $false,ValueFromPipeline = $false)]
    [string]$IndentText = '  ',
    [switch]$Quiet
  )
  #endregion
  process {

    [datetime]$StartTime = Get-Date

    # initialize valid lookup names used by beautifier if not initialized yet (lazy load)
    if ($MyInvocation.MyCommand.Module.PrivateData['ValidNamesInitialized'] -eq $false) {
      Initialize-DTWBeautifyValidNames
    }

    #region Initialize script-level variables
    # initialize all script-level variables used in a cleaning process
    Initialize-ProcessVariables
    # if not initialize properly, exit
    if ($false -eq $ModuleInitialized) {
      Write-Error -Message 'Module not properly initialized; exiting.'
      return
    }
    #endregion

    #region Parameter validation and path testing
    # resolve path so make sure we have full name
    $SourcePath = Resolve-Path -Path $SourcePath

    #region SourcePath must exist; if not, exit
    if ($false -eq (Test-Path -Path $SourcePath)) {
      Write-Error -Message "SourcePath does not exist: $SourcePath"
      return
    }
    #endregion

    #region SourcePath must be a file, not a folder
    if ($true -eq ((Get-Item -Path $SourcePath)).PSIsContainer) {
      Write-Error -Message " SourcePath is a folder, not a file: $SourcePath"
      return
    }
    #endregion

    #region If source file contains no content just exit
    if ((Get-Item -Path $SourcePath).Length -eq 0 -or ([System.IO.File]::ReadAllText($SourcePath)).Trim() -eq '') {
      return
    }
    #endregion

    #region Test IndentText and set script level variable
    # if user wants tabs for indents but passed '`t' they probably meant "`t" so change for them
    if ($IndentText -eq '`t') {
      $IndentText = "`t"
    }
    # set script level variable
    $script:IndentText = $IndentText
    #endregion
    #endregion

    #region Set source, destination and temp file paths
    $script:SourcePath = $SourcePath
    # if no destination passed, use source (i.e. rewrite in place)
    if (($DestinationPath -eq $null) -or ($DestinationPath.Trim() -eq '')) {
      # set script level variable
      $script:DestinationPath = $SourcePath
    } else {
      # $DestinationPath specified
      # if destination doesn't exist, assume path correct as-is
      if ($false -eq (Test-Path -Path $DestinationPath)) {
        # set script level variable
        $script:DestinationPath = $DestinationPath
      } else {
        # resolve path so make sure we have full name
        $DestinationPath = Resolve-Path -Path $DestinationPath
        # if user specified a folder for DestinationPath, set DestinationPath value to folder + source file name
        if ($true -eq ((Get-Item -Path $DestinationPath).PSIsContainer)) {
          $DestinationPath = Join-Path -Path $DestinationPath -ChildPath (Split-Path -Path $SourcePath -Leaf)
        }
        # set script level variable
        $script:DestinationPath = $DestinationPath
      }
    }
    # set temp file to destination path plus unique date time stamp
    $script:DestinationPathTemp = $script:DestinationPath + ('.{0:yyyyMMdd_HHmmss}' -f $StartTime) + '.pspp'
    #endregion

    #region Copy source file to destination temp and add BOM if necessary
    #region Notes about temp file and Byte Order Marker (BOM)
    <#
    There are two situations handled below that are worth describing in more detail:
    1. We don't want to overwrite source file until we know the entire process worked successfully.
    This is obvious; the last thing we want to do is for an exception to occur halfway through the
    rewrite process and the source script to be lost.  To that end a temp file is used; it is created in
    the same folder and has the same name as the source but with a date time stamp and .pspp as the extension.
    Once the cleanup/write process is complete on the temp file, the original source is deleted and the
    temp is renamed.  In the event of an error, the temp file can be reviewed.
    2. If your PowerShell file has Unicode characters in it, it most likely has a byte order mark,
    or BOM, at the beginning of the file.  Depending on your editor, and which Unicode characters you
    enter, the file might be missing it.  Here's the thing: most PowerShell Unicode files without a 
    BOM won't even run in PowerShell (some UTF8 will; it depends on which characters are there) BUT 
    this beautify/cleanup script will not work without that BOM.  (The tokenize method will fail.)
    To fix this: when the temp file (from #1 above) is created as a copy of the source, it is then 
    checked to see if it has a BOM.  If none is detected but Unicode characters are, the BOM is 
    added.  For 99.99999999% of cases, this should be an acceptable situation.  I can't imagine a 
    use case in which having a PS script that won't run in PowerShell (or in this script) because of 
    a missing BOM is a good thing.
    #>
    #endregion

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPathTemp -Force
    # if file is non-ASCII and doesn't have byte order marker, rewrite file in place with BOM
    $TempFileEncoding = Get-DTWFileEncoding -Path $DestinationPathTemp

    # check what name used in past - EnncodingName, BodyName?  HeaderName?
    # if not ASCII and no BOM, rewrite with BOM
    if (($TempFileEncoding -ne [System.Text.Encoding]::ASCII) -and ($TempFileEncoding.GetPreamble().Length -eq 0)) {
      # add BOM using FileEncoding
      Add-DTWFileEncodingByteOrderMarker -Path $DestinationPathTemp -FileEncoding $TempFileEncoding
    }
    #endregion

    #region Read source script content content into memory
    if (!$Quiet) { Write-Host "Reading source: $SourcePath" }
    $Err = $null
    Import-ScriptContent -EV $Err
    # if an error occurred importing content, it will be written from Import-ScriptContent
    # so in this case just exit
    if ($null -ne $Err) { return }
    #endregion

    #region Tokenize source script content
    $Err = $null
    if (!$Quiet) { Write-Host 'Tokenizing script content' }
    Invoke-TokenizeSourceScriptContent -EV Err
    # if an error occurred tokenizing content, it will be written from Invoke-TokenizeSourceScriptContent
    # so in this case just initialize the process variables and exit
    if ($null -ne $Err -and $Err.Count) {
      Initialize-ProcessVariables
      return
    }
    #endregion

    # create stream writer in try/catch so can dispose if error
    try {
      #region
      # Destination content is stored in a stream which is written to the file at the end.
      # It has to be a stream; storing it in a string or string builder loses the original
      # values (with regard to escaped characters).

      # if parent destination folder doesn't exist, create
      [string]$Folder = Split-Path -Path $DestinationPathTemp -Parent
      if ($false -eq (Test-Path -Path $Folder)) { New-Item -Path $Folder -ItemType Directory > $null }

      # create file stream writer, overwrite - don't append, and use same encoding as source file
      $script:DestinationStreamWriter = New-Object System.IO.StreamWriter $DestinationPathTemp,$false,$SourceFileEncoding
      #endregion
      # create new tokens for destination script content
      if (!$Quiet) { Write-Host 'Migrate source content to destination format' }
      Copy-SourceContentToDestinationStream
    } catch {
      Write-Error -Message "$($MyInvocation.MyCommand.Name) :: error occurred during processing"
      Write-Error -Message "$($_.ToString())"
      return
    } finally {
      #region Flush and close file stream writer
      if (!$Quiet) { Write-Host "Write destination file: $script:DestinationPath" }
      if ($null -ne $script:DestinationStreamWriter) {
        $script:DestinationStreamWriter.Flush()
        $script:DestinationStreamWriter.Close()
        $script:DestinationStreamWriter.Dispose()
        #region Replace destination file with destination temp (which has updated content)
        # if destination file already exists, remove it
        if ($true -eq (Test-Path -Path $script:DestinationPath)) { Remove-Item -Path $script:DestinationPath -Force }
        # rename destination temp to destination
        Rename-Item -Path $DestinationPathTemp -NewName (Split-Path -Path $script:DestinationPath -Leaf)
        #endregion
      }
      #endregion
      if (!$Quiet) { Write-Host ("Finished in {0:0.000} seconds.`n" -f ((Get-Date) - $StartTime).TotalSeconds) }
    }
  }
}
Export-ModuleMember -Function Edit-DTWBeautifyScript
#endregion
