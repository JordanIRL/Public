# Microsoft Teams

`MicrosoftTeams` 7.9.0 — `Connect-MicrosoftTeams` (Windows PowerShell 5.1 or PowerShell 7.2+, cross-platform).

## Connect

### Sign in interactively
```powershell
Connect-MicrosoftTeams
```
No parameters needed for the normal admin case; the MFA browser prompt appears automatically. No app registration is required — a Microsoft first-party app is used.

### Sign in when your account exists in several tenants
```powershell
Connect-MicrosoftTeams -TenantId contoso.onmicrosoft.com -AccountId admin@contoso.onmicrosoft.com
```

### Sign in on a machine with no browser
```powershell
Connect-MicrosoftTeams -UseDeviceAuthentication
```

### Verify the connection
```powershell
Get-CsTenant | Select-Object DisplayName, TenantId
```

### Disconnect
```powershell
Disconnect-MicrosoftTeams
```

## Teams lifecycle

### List every team in the tenant
```powershell
Get-Team | Select-Object DisplayName, MailNickName, Visibility, Archived, GroupId
```
`Get-Team` with no filter enumerates the whole tenant and is slow; `-NumberOfThreads` (1–20, default 20) is the only tuning knob.

### Find a team by display name
```powershell
Get-Team -DisplayName "Sales Team"
```
Case-sensitive substring filter, not an exact match — expect several hits. Escape special characters with `[uri]::EscapeDataString()`.

### List archived teams
```powershell
Get-Team -Archived $true | Select-Object DisplayName, GroupId
```
Omit `-Archived` entirely to get teams regardless of archive state; `$false` returns only live ones.

### Create a team
```powershell
New-Team -DisplayName "Sales Team" -MailNickName "salesteam" -Description "Sales collaboration" -Visibility Private -Owner user@contoso.com
```
Returns an object with a `GroupId`. Teams created this way are hidden from Outlook unless you clear `HiddenFromExchangeClientsEnabled` with `Set-UnifiedGroup`.

### Team-enable an existing Microsoft 365 group
```powershell
New-Team -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -Owner user@contoso.com
```
Use the `ExternalDirectoryObjectId` from `Get-UnifiedGroup`. You cannot pass DisplayName/Visibility/Description in this parameter set.

### Change visibility or team settings
```powershell
Set-Team -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -Visibility Public -AllowCreatePrivateChannels $false -AllowDeleteChannels $false
```

### Archive a team and lock its SharePoint site
```powershell
Set-TeamArchivedState -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -Archived $true -SetSpoSiteReadOnlyForMembers $true
```

### Unarchive a team
```powershell
Set-TeamArchivedState -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -Archived $false
```

### Delete a team
```powershell
Remove-Team -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d
```
Deletes the backing Microsoft 365 group too. Soft-deleted for 30 days.

### Restore a deleted team (Graph only)
```powershell
Restore-MgDirectoryDeletedItem -DirectoryObjectId 105b16e2-dc55-4f37-a922-97551e9e862d
```
No Teams cmdlet exists. Connect with `Connect-MgGraph -Scopes "Group.ReadWrite.All"`; list candidates with `Get-MgDirectoryDeletedItemAsGroup`. Content can take 24 hours to reappear.

### Clone a team (Graph only)
```powershell
Copy-MgTeam -TeamId 105b16e2-dc55-4f37-a922-97551e9e862d -BodyParameter @{ displayName = "Sales Team 2026"; mailNickname = "salesteam2026"; partsToClone = "apps,tabs,settings,channels,members"; visibility = "private" }
```
Long-running async operation; cloned tabs come back unconfigured. Requires the `Team.Create` or `Group.ReadWrite.All` scope.

## Channels

### List channels hosted by a team
```powershell
Get-TeamChannel -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d
```

### List every channel including shared-in channels
```powershell
Get-TeamAllChannel -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d
```
`Get-TeamChannel` only sees channels the team hosts; `Get-TeamAllChannel` also returns incoming shared channels. Add `-MembershipType Shared` to list shared channels alone.

### Create a standard, private or shared channel
```powershell
New-TeamChannel -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -DisplayName "Bids" -MembershipType Private -Owner user@contoso.com
```
`-MembershipType` accepts Standard, Private or Shared.

### Rename a channel
```powershell
Set-TeamChannel -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -CurrentDisplayName "Bids" -NewDisplayName "Bids and Tenders"
```

### Delete a channel
```powershell
Remove-TeamChannel -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -DisplayName "Bids"
```
Soft delete — but the channel name can **never** be reused, even after the 30-day restore window (by design, for information protection). Restoring a deleted channel is a Teams client / admin center action, not a cmdlet.

### List members of a private or shared channel
```powershell
Get-TeamChannelUser -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -DisplayName "Bids"
```
Add `-Role Owner` to see only the channel owners.

### Add someone to a private or shared channel
```powershell
Add-TeamChannelUser -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -DisplayName "Bids" -User user@contoso.com -Role Owner
```
A user must already be a team member before becoming a channel member, and a channel member before becoming a channel owner.

### Add an external user to a shared channel
```powershell
Add-TeamChannelUser -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -DisplayName "Bids" -User user@fabrikam.com -TenantId 38aad667-af54-4397-aaa7-e94c79ec2308
```
`-TenantId` is the external user's home tenant.

### Remove someone from a channel
```powershell
Remove-TeamChannelUser -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -DisplayName "Bids" -User user@contoso.com
```
Passing `-Role Owner` demotes an owner to member instead of removing them.

## Membership

### List owners and members of a team
```powershell
Get-TeamUser -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d | Sort-Object Role, Name
```

### Add a member or an owner
```powershell
Add-TeamUser -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -User user@contoso.com -Role Owner
```
Adding as Owner also adds the user as a member of the backing group. Client can take 24–48 hours to reflect the change.

### Remove a member, or demote an owner
```powershell
Remove-TeamUser -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d -User user@contoso.com -Role Owner
```
With `-Role Owner` the user stays a member. The last owner cannot be removed.

### Bulk add from CSV
```powershell
Import-Csv .\members.csv | ForEach-Object { Add-TeamUser -GroupId $_.GroupId -User $_.User -Role $_.Role }
```
CSV columns: `GroupId,User,Role`.

### Find every team a user belongs to
```powershell
Get-Team -User user@contoso.com | Select-Object DisplayName, GroupId
```

### List the guests in a team
```powershell
Get-TeamUser -GroupId 105b16e2-dc55-4f37-a922-97551e9e862d | Where-Object { $_.User -like "*#EXT#*" }
```

### Find teams with no owner
```powershell
Get-Team | Where-Object { @(Get-TeamUser -GroupId $_.GroupId -Role Owner).Count -eq 0 } | Select-Object DisplayName, GroupId
```
One `Get-TeamUser` call per team — throttles on large tenants, so run it in batches or overnight.

## Policies

### List the instances of a policy type
```powershell
Get-CsTeamsMeetingPolicy | Select-Object Identity, Description
```
Same pattern for `Get-CsTeamsMessagingPolicy`, `Get-CsTeamsCallingPolicy`, `Get-CsTeamsMeetingBroadcastPolicy` (live events), `Get-CsTeamsAppSetupPolicy`, `Get-CsExternalAccessPolicy`, `Get-CsOnlineVoiceRoutingPolicy`.

### Assign a policy to one user
```powershell
Grant-CsTeamsMeetingPolicy -Identity user@contoso.com -PolicyName "Restricted Meetings"
```

### Remove a direct assignment so group or global policy applies again
```powershell
Grant-CsTeamsMeetingPolicy -Identity user@contoso.com -PolicyName $null
```

### Assign a policy to everyone in a group
```powershell
Grant-CsTeamsMeetingPolicy -Group d8ebfa45-0f28-4d2d-9bcc-b158a49e2d17 -PolicyName "Restricted Meetings" -Rank 1
```
`-Group` takes a group **object ID, SIP address or email address** — a display name fails. Rank 1 is highest; direct user assignments always beat group assignments.

### List and remove group policy assignments
```powershell
Get-CsGroupPolicyAssignment -PolicyType TeamsMeetingPolicy
Remove-CsGroupPolicyAssignment -GroupId d8ebfa45-0f28-4d2d-9bcc-b158a49e2d17 -PolicyType TeamsMeetingPolicy
```

### See which policy a user actually gets, and where it came from
```powershell
Get-CsUserPolicyAssignment -Identity user@contoso.com -PolicyType TeamsMeetingPolicy | Select-Object -ExpandProperty PolicySource
```
`Get-CsOnlineUser` only shows *direct* assignments — this is the cmdlet that resolves group inheritance.

### Assign a policy to a batch of users
```powershell
New-CsBatchPolicyAssignmentOperation -PolicyType TeamsMessagingPolicy -PolicyName "New Hire Messaging" -Identity user1@contoso.com,user2@contoso.com -OperationName "New hires August"
```
Max 5,000 users per batch. Identify users by object ID or **SIP address** — a UPN that differs from the SIP address fails silently for that user. Supported types include TeamsMeetingPolicy, TeamsMessagingPolicy, TeamsCallingPolicy, TeamsAppSetupPolicy, TeamsAppPermissionPolicy, TeamsMeetingBroadcastPolicy, ExternalAccessPolicy, OnlineVoiceRoutingPolicy, TenantDialPlan.

### Check batch progress
```powershell
Get-CsBatchPolicyAssignmentOperation -Identity f985e013-0826-40bb-8c94-e5f367076044 | Format-List
```

### See the per-user errors in a batch
```powershell
Get-CsBatchPolicyAssignmentOperation -Identity f985e013-0826-40bb-8c94-e5f367076044 | Select-Object -ExpandProperty UserState
```
Operations are only retained for 30 days.

## Meeting settings

### Read the org-wide meeting configuration
```powershell
Get-CsTeamsMeetingConfiguration
```

### Allow or block anonymous join org-wide
```powershell
Set-CsTeamsMeetingConfiguration -Identity Global -DisableAnonymousJoin $false
```
Microsoft recommends leaving this `$false` and controlling anonymous join per organizer in the meeting policy.

### Control anonymous join per organizer
```powershell
Set-CsTeamsMeetingPolicy -Identity "Restricted Meetings" -AllowAnonymousUsersToJoinMeeting $false -AllowAnonymousUsersToStartMeeting $false -AllowAnonymousUsersToDialOut $false
```

### Set who bypasses the lobby
```powershell
Set-CsTeamsMeetingPolicy -Identity "Restricted Meetings" -AutoAdmittedUsers EveryoneInCompany
```

### Require anonymous attendees to verify by email code
```powershell
Set-CsTeamsMeetingPolicy -Identity "Restricted Meetings" -AnonymousUserAuthenticationMethod OneTimePasscode
```

### Stop anonymous participants using apps in meetings
```powershell
Set-CsTeamsMeetingConfiguration -Identity Global -DisableAppInteractionForAnonymousUsers $true
```

## Guest and external access

### Read the current federation configuration
```powershell
Get-CsTenantFederationConfiguration | Format-List AllowFederatedUsers, AllowedDomains, BlockedDomains, AllowTeamsConsumer, ExternalAccessWithTrialTenants
```

### Turn external access off entirely
```powershell
Set-CsTenantFederationConfiguration -AllowFederatedUsers $false
```
Master switch: when `$false`, allow/block lists and per-user `ExternalAccessPolicy` are all ignored.

### Allow only specific domains
```powershell
Set-CsTenantFederationConfiguration -AllowedDomainsAsAList @("fabrikam.com","adventure-works.com")
```
`-AllowedDomains` cannot take plain strings — it needs an object from `New-CsEdgeAllowList` / `New-CsEdgeAllowAllKnownDomains`. `-AllowedDomainsAsAList` is the string-friendly path, and also accepts `@{Add=$list}` / `@{Remove=$list}`.

### Allow everyone except blocked domains
```powershell
Set-CsTenantFederationConfiguration -AllowedDomains (New-CsEdgeAllowAllKnownDomains)
```

### Block one domain without touching the rest of the list
```powershell
Set-CsTenantFederationConfiguration -BlockedDomains @{Add=(New-CsEdgeDomainPattern -Domain "fabrikam.com")}
```
Use `@{Remove=...}` to unblock, `@{Replace=...}` to overwrite, `$null` to clear the list. `-BlockAllSubdomains $true` extends the block to subdomains.

### Control chat with personal (consumer) Teams accounts
```powershell
Set-CsTenantFederationConfiguration -AllowTeamsConsumer $true -AllowTeamsConsumerInbound $false
```
Inbound `$false` means your users can start those chats but outsiders cannot start one with them.

### Block tenants that hold only trial licences
```powershell
Set-CsTenantFederationConfiguration -ExternalAccessWithTrialTenants "Blocked" -AllowedTrialTenantDomains @("fabrikam.com")
```

### Turn guest access on or off in the Teams client
```powershell
Set-CsTeamsClientConfiguration -Identity Global -AllowGuestUser $true
```
This is the Teams-side switch only; guests must also be permitted in Entra external collaboration settings.

### Restrict what guests can do in chat
```powershell
Set-CsTeamsGuestMessagingConfiguration -AllowUserChat $true -AllowUserDeleteMessage $false -AllowGiphy $false
```

## Apps

### List every app in the tenant catalog
```powershell
Get-AllM365TeamsApps | Select-Object Id, IsBlocked, AvailableTo, InstalledFor
```
Those four are the only properties this cmdlet returns; use `Get-TeamsApp` for names and publishers.

### Inspect one app
```powershell
Get-M365TeamsApp -Id 4c4ec2e8-4a2c-4bce-8d8f-00fc664a4e5b
```

### Block an app tenant-wide
```powershell
Update-M365TeamsApp -Id 4c4ec2e8-4a2c-4bce-8d8f-00fc664a4e5b -IsBlocked $true
```

### Make an app available only to specific groups
```powershell
Update-M365TeamsApp -Id 4c4ec2e8-4a2c-4bce-8d8f-00fc664a4e5b -AppAssignmentType UsersAndGroups -OperationType Add -Groups 37da2d58-fc14-453e-9a14-5065ebd63a1d
```
`-Groups` takes group **object IDs**, not display names. Use `-AppAssignmentType Everyone` to open it up again; up to 99 users or groups per app.

### Assign an app setup policy
```powershell
Grant-CsTeamsAppSetupPolicy -Identity user@contoso.com -PolicyName "Frontline Pinned Apps"
```
App **permission** policies (`Grant-CsTeamsAppPermissionPolicy`) only apply to tenants not yet migrated to app centric management; after migration, use `Update-M365TeamsApp` instead.

## Teams Phone

### List acquired phone numbers
```powershell
Get-CsPhoneNumberAssignment -Top 1000
```
Returns 500 by default, 1000 max — page with `-Skip`/`-Top`, or use `Export-CsAcquiredPhoneNumber` for the full list.

### Find unassigned user numbers
```powershell
Get-CsPhoneNumberAssignment -PstnAssignmentStatus Unassigned -CapabilitiesContain UserAssignment
```

### Show the number assigned to a user or resource account
```powershell
Get-CsPhoneNumberAssignment -AssignedPstnTargetId user@contoso.com
```

### Assign a number with an emergency location
```powershell
Set-CsPhoneNumberAssignment -Identity user@contoso.com -TelephoneNumber +12065551234 -NumberType CallingPlan -LocationId 407c17ae-8c41-431e-894a-38787c682f68
```
`-NumberType` is DirectRouting, CallingPlan or OperatorConnect. Assigning a number sets `EnterpriseVoiceEnabled` to true automatically.

### Unassign a number
```powershell
Remove-CsPhoneNumberAssignment -Identity user@contoso.com -TelephoneNumber +12065551234 -NumberType CallingPlan
```

### Change only the emergency location on a number
```powershell
Set-CsPhoneNumberAssignment -TelephoneNumber +12065551234 -LocationId 407c17ae-8c41-431e-894a-38787c682f68
```
Pass the string `'null'` as the LocationId to remove the location (Direct Routing and unmanaged Operator Connect numbers only).

### List emergency addresses and locations
```powershell
Get-CsOnlineLisCivicAddress | Select-Object CivicAddressId, HouseNumber, StreetName, City
Get-CsOnlineLisLocation -City "Seattle" | Select-Object LocationId, Location
```

### Add a location inside an existing civic address
```powershell
New-CsOnlineLisLocation -CivicAddressId b39ff77d-db51-4ce5-8d50-9e9c778e1617 -Location "Office 101, 1st Floor"
```

### Assign a voice routing policy
```powershell
Grant-CsOnlineVoiceRoutingPolicy -Identity user@contoso.com -PolicyName "US Only"
```
`-Group <object-id> -Rank 1` assigns it by group (object ID, SIP or email — not a display name); `-Global` sets the tenant default.

### List auto attendants and call queues
```powershell
Get-CsAutoAttendant -First 100 | Select-Object Identity, Name, LanguageId
Get-CsCallQueue -First 100 | Select-Object Identity, Name, RoutingMethod
```
Add `-ExcludeContent` for a fast name-only listing on large estates.

### Inspect a resource account and what it is attached to
```powershell
Get-CsOnlineApplicationInstance -Identity aa1@contoso.com
Get-CsOnlineApplicationInstanceAssociation -Identity aa1@contoso.com
```

## Reporting

### Export a team inventory
```powershell
Get-Team | Select-Object DisplayName, MailNickName, Visibility, Archived, GroupId | Export-Csv .\teams.csv -NoTypeInformation
```

### Count channels per team
```powershell
Get-Team | ForEach-Object { [pscustomobject]@{ Team = $_.DisplayName; Channels = @(Get-TeamAllChannel -GroupId $_.GroupId).Count } }
```

### List Teams-licensed users
```powershell
Get-CsOnlineUser -Filter "FeatureTypes -contains 'Teams'" -ResultSize Unlimited | Select-Object DisplayName, UserPrincipalName, AccountType
```

### List voice-enabled users
```powershell
Get-CsOnlineUser -Filter {(EnterpriseVoiceEnabled -eq $True) -and (FeatureTypes -contains 'PhoneSystem') -and (AccountEnabled -eq $True)} -AccountType User
```

### Show a user's Teams configuration
```powershell
Get-CsOnlineUser -Identity user@contoso.com | Format-List DisplayName, SipAddress, LineUri, EnterpriseVoiceEnabled, FeatureTypes, TeamsMeetingPolicy, TeamsMessagingPolicy
```

## Gotchas

- Use Graph, not this module, for group membership at scale (`Get-MgGroupMember`), deleted-team restore, and cloning; `Add-TeamUser`/`Get-TeamUser` are one-team-at-a-time and throttle hard. Cs* policy, voice, federation and app-centric cmdlets exist **only** here.
- `Get-Team -DisplayName` / `-MailNickName` are case-sensitive substring filters, not exact matches — always check `GroupId` before acting.
- Changes are eventually consistent: membership can take 24–48 hours to show in the client, group policy assignment 24 hours or more to propagate to large groups.
- Direct user policy assignments always beat group assignments; `Get-CsOnlineUser` shows only direct ones, so audit with `Get-CsUserPolicyAssignment`.
- A policy type can be assigned to at most 64 groups, and group assignments never reach members of nested groups.
- Batch policy assignment matches on SIP address. If a user's UPN and SIP address differ, the batch reports "User not found" for them and keeps going.
- `Get-CsPhoneNumberAssignment` silently caps at 500 results (1000 with `-Top`) — page with `-Skip` or you will "lose" numbers.
- `Set-CsPhoneNumberAssignment` cannot set a number that was synced from on-premises AD; clear it in AD first.
- `-AllowedDomains` rejects plain strings; use `-AllowedDomainsAsAList`, or build an object with `New-CsEdgeAllowList` / `New-CsEdgeAllowAllKnownDomains`.
- Setting `AllowFederatedUsers $false` overrides every allow list and every `ExternalAccessPolicy` instance.
- App permission policies are read-only dead weight once a tenant is migrated to app centric management — `Update-M365TeamsApp` is the live control.
- Some channel-user cmdlets (`Add-/Remove-/Get-TeamChannelUser`) still carry a public-preview note in the docs; behaviour changes between module versions.
- Requires the Teams Administrator role (Teams Communications Administrator for policy batches); Global Administrator is not needed and should not be used.
- Every workload needs its own connect: `Disconnect-MicrosoftTeams` closes only this one, not Exchange, Graph, PnP or SPO. Never run `Update-Module MicrosoftTeams` while the module is imported.
