# Microsoft Teams and Outlook Room Lists: Create, Change, Delete, and Validate

**Last updated:** 10 July 2026  
**Applies to:** Exchange Online, Microsoft Teams meeting scheduling, Outlook Room Finder  
**Scope:** Exchange room lists only. This guide does not use Microsoft Places, Places Finder, the MicrosoftPlaces PowerShell module, or a Places building hierarchy.

## Purpose

Use this guide to:

- Create a new room list that appears as a building or location grouping in Teams and Outlook.
- Add or remove room mailboxes from a room list.
- Move rooms from an old room list to a replacement room list.
- Rename a room list.
- Convert an ordinary distribution group into a room list.
- Delete a retired room list without deleting its room mailboxes.
- Prove, from Exchange Online, whether the configuration is correct before waiting for client propagation.

## What a room list actually is

A room list is an Exchange distribution group with a special room-list flag. It is not:

- A Microsoft 365 group.
- A Teams team.
- A Teams Rooms Pro object.
- A Microsoft Places building.
- A normal distribution group that merely contains room mailboxes.

The decisive property is:

```text
RecipientTypeDetails : RoomList
```

Room Finder displays room lists as values in its **Building** filter. Microsoft documents that this building value comes from the room list, not from the `Building` property on an individual room mailbox.

A correct room-list deployment therefore has two layers:

1. A distribution group whose `RecipientTypeDetails` is `RoomList`.
2. Direct members that are the room or workspace resource mailboxes users should find under that list.

## Expected propagation

Exchange Online PowerShell normally reflects a successful change immediately.

Teams and Outlook do not necessarily reflect it immediately. Microsoft documents a **24 to 48 hour** propagation period after Room Finder configuration is created or modified. Use that window after you:

- Create a room list.
- Rename a room list.
- Add or remove members.
- Delete a room list and wait for its old client entry to disappear.

Do not use a Teams desktop cache as the first test. Confirm Exchange Online first, then test a web client, and only then troubleshoot a local client.

## Prerequisites

Use PowerShell 7 and the Exchange Online Management module.

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline -ShowBanner:$false
```

Typical administrative access is Exchange Administrator. Some group operations can additionally require one of the following when the signed-in administrator is not an owner of the group:

- Organization Management.
- Security Group Creation and Membership.
- The `-BypassSecurityGroupManagerCheck` switch.

This guide uses Exchange Online PowerShell. Teams PowerShell and Microsoft Graph are not required.

## First: determine the source of authority

Before modifying or deleting a room list, inspect it:

```powershell
Get-DistributionGroup -Identity "buildingrooms@contoso.com" |
    Format-List Name,
                DisplayName,
                Alias,
                PrimarySmtpAddress,
                RecipientTypeDetails,
                ManagedBy,
                IsDirSynced,
                WhenCreatedUTC,
                WhenChangedUTC
```

Interpret `IsDirSynced` as follows:

| Value | Meaning |
|---|---|
| `False` | The room list is cloud-managed. Make the change in Exchange Online. |
| `True` | The object is synchronised. Make the change in the authoritative on-premises Exchange or directory environment and allow synchronisation to complete. |

Do not delete or repeatedly modify a synchronised object in Exchange Online and expect the cloud change to remain.

---

# Read-only validation

## Five-minute validation

Edit the identity and run these commands:

```powershell
$RoomList = "buildingrooms@contoso.com"

Get-DistributionGroup -Identity $RoomList |
    Format-List Name,
                DisplayName,
                Alias,
                PrimarySmtpAddress,
                RecipientTypeDetails,
                HiddenFromAddressListsEnabled,
                ManagedBy,
                IsDirSynced,
                WhenChangedUTC

Get-DistributionGroupMember -Identity $RoomList -ResultSize Unlimited |
    Sort-Object DisplayName |
    Format-Table DisplayName,
                 PrimarySmtpAddress,
                 RecipientType,
                 RecipientTypeDetails -AutoSize
```

A correct result has:

- `RecipientTypeDetails` equal to `RoomList`.
- The intended display name.
- The intended primary SMTP address.
- Every expected room listed as a direct member.
- No normal user mailboxes, shared mailboxes, contacts, or ordinary groups included as members.
- `IsDirSynced` matching the management method you used.

## List every room list in the tenant

```powershell
Get-DistributionGroup `
    -RecipientTypeDetails RoomList `
    -ResultSize Unlimited |
    Sort-Object DisplayName |
    Format-Table DisplayName,
                 PrimarySmtpAddress,
                 Alias,
                 HiddenFromAddressListsEnabled,
                 IsDirSynced,
                 WhenChangedUTC -AutoSize
```

This is one of the most useful checks. If a group can be found with `Get-DistributionGroup -Identity` but does not appear in this output, it is not currently a room list.

## Comprehensive read-only validator

Edit only the variables at the top. The script does not create, modify, or delete anything.

```powershell
#requires -Version 7.0

# ============================================================
# EDIT THESE VALUES
# ============================================================

$TargetRoomList  = "newbuildingrooms@contoso.com"
$RetiredRoomList = "oldbuildingrooms@contoso.com"

$ExpectedRooms = @(
    "room1@contoso.com",
    "room2@contoso.com"
)

# ============================================================
# CONNECT
# ============================================================

Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline -ShowBanner:$false

# ============================================================
# ALL ROOM LISTS
# ============================================================

$AllRoomLists = Get-DistributionGroup `
    -RecipientTypeDetails RoomList `
    -ResultSize Unlimited

Write-Host "`n=== ALL ROOM LISTS ===" -ForegroundColor Cyan

$AllRoomLists |
    Sort-Object DisplayName |
    Select-Object DisplayName,
                  PrimarySmtpAddress,
                  Alias,
                  HiddenFromAddressListsEnabled,
                  IsDirSynced,
                  WhenChangedUTC |
    Format-Table -AutoSize

# ============================================================
# TARGET AND RETIRED OBJECTS
# ============================================================

$Target = Get-DistributionGroup `
    -Identity $TargetRoomList `
    -ErrorAction SilentlyContinue

$Retired = Get-DistributionGroup `
    -Identity $RetiredRoomList `
    -ErrorAction SilentlyContinue

Write-Host "`n=== TARGET ROOM LIST ===" -ForegroundColor Cyan

if (-not $Target) {
    Write-Warning "Target object was not found: $TargetRoomList"
}
else {
    $Target |
        Format-List Name,
                    DisplayName,
                    Alias,
                    PrimarySmtpAddress,
                    RecipientTypeDetails,
                    HiddenFromAddressListsEnabled,
                    ManagedBy,
                    IsDirSynced,
                    WhenChangedUTC

    if ($Target.RecipientTypeDetails -ne "RoomList") {
        Write-Warning "The target exists but is not a RoomList."
    }
}

Write-Host "`n=== RETIRED ROOM LIST ===" -ForegroundColor Cyan

if (-not $Retired) {
    Write-Host "Retired object is absent. This is expected after deletion."
}
else {
    $Retired |
        Format-List Name,
                    DisplayName,
                    Alias,
                    PrimarySmtpAddress,
                    RecipientTypeDetails,
                    HiddenFromAddressListsEnabled,
                    ManagedBy,
                    IsDirSynced,
                    WhenChangedUTC
}

# ============================================================
# MEMBERSHIPS
# ============================================================

$TargetMembers = @()

if ($Target) {
    $TargetMembers = @(
        Get-DistributionGroupMember `
            -Identity $Target.PrimarySmtpAddress `
            -ResultSize Unlimited
    )
}

$RetiredMembers = @()

if ($Retired) {
    $RetiredMembers = @(
        Get-DistributionGroupMember `
            -Identity $Retired.PrimarySmtpAddress `
            -ResultSize Unlimited
    )
}

Write-Host "`n=== TARGET MEMBERS ===" -ForegroundColor Cyan

$TargetMembers |
    Sort-Object DisplayName |
    Format-Table DisplayName,
                 PrimarySmtpAddress,
                 RecipientType,
                 RecipientTypeDetails -AutoSize

Write-Host "`n=== RETIRED MEMBERS ===" -ForegroundColor Cyan

$RetiredMembers |
    Sort-Object DisplayName |
    Format-Table DisplayName,
                 PrimarySmtpAddress,
                 RecipientType,
                 RecipientTypeDetails -AutoSize

# Build a tenant-wide direct membership map.
$MembershipMap = foreach ($List in $AllRoomLists) {
    $Members = Get-DistributionGroupMember `
        -Identity $List.PrimarySmtpAddress `
        -ResultSize Unlimited `
        -ErrorAction SilentlyContinue

    foreach ($Member in $Members) {
        [pscustomobject]@{
            RoomListName = $List.DisplayName
            RoomListSmtp = $List.PrimarySmtpAddress.ToString()
            MemberName   = $Member.DisplayName
            MemberSmtp   = $Member.PrimarySmtpAddress.ToString().ToLowerInvariant()
            MemberType   = $Member.RecipientTypeDetails
        }
    }
}

# ============================================================
# EXPECTED ROOM RESULTS
# ============================================================

Write-Host "`n=== EXPECTED ROOM VALIDATION ===" -ForegroundColor Cyan

$TargetSmtp = if ($Target) {
    $Target.PrimarySmtpAddress.ToString()
}
else {
    $null
}

$RetiredSmtp = if ($Retired) {
    $Retired.PrimarySmtpAddress.ToString()
}
else {
    $null
}

$ExpectedResults = foreach ($ExpectedRoom in $ExpectedRooms) {
    $ExpectedAddress = $ExpectedRoom.ToLowerInvariant()
    $Memberships = @(
        $MembershipMap |
            Where-Object MemberSmtp -eq $ExpectedAddress
    )

    try {
        $Mailbox = Get-Mailbox -Identity $ExpectedRoom -ErrorAction Stop

        [pscustomobject]@{
            Room                  = $ExpectedRoom
            MailboxType           = $Mailbox.RecipientTypeDetails
            HiddenFromAddressList = $Mailbox.HiddenFromAddressListsEnabled
            InTargetRoomList      = [bool](
                $TargetSmtp -and
                $Memberships.RoomListSmtp -contains $TargetSmtp
            )
            InRetiredRoomList     = [bool](
                $RetiredSmtp -and
                $Memberships.RoomListSmtp -contains $RetiredSmtp
            )
            AllRoomLists          = $Memberships.RoomListName -join "; "
        }
    }
    catch {
        [pscustomobject]@{
            Room                  = $ExpectedRoom
            MailboxType           = "NOT FOUND"
            HiddenFromAddressList = $null
            InTargetRoomList      = $false
            InRetiredRoomList     = $false
            AllRoomLists          = $Memberships.RoomListName -join "; "
        }
    }
}

$ExpectedResults | Format-Table -AutoSize

# ============================================================
# REVIEW CONDITIONS
# ============================================================

Write-Host "`n=== ITEMS REQUIRING REVIEW ===" -ForegroundColor Cyan

$DuplicateMemberships = $MembershipMap |
    Group-Object MemberSmtp |
    Where-Object Count -gt 1

if ($DuplicateMemberships) {
    Write-Warning "The following rooms belong to multiple room lists:"

    foreach ($Duplicate in $DuplicateMemberships) {
        $Duplicate.Group |
            Select-Object MemberSmtp,
                          RoomListName,
                          RoomListSmtp |
            Format-Table -AutoSize
    }
}
else {
    Write-Host "No duplicate room-list memberships were found."
}

$UnexpectedTargetMembers = $TargetMembers |
    Where-Object RecipientTypeDetails -notin @(
        "RoomMailbox",
        "RemoteRoomMailbox"
    )

if ($UnexpectedTargetMembers) {
    Write-Warning "The target contains member types that require review:"

    $UnexpectedTargetMembers |
        Format-Table DisplayName,
                     PrimarySmtpAddress,
                     RecipientTypeDetails -AutoSize
}
else {
    Write-Host "No unexpected target member types were found."
}

Disconnect-ExchangeOnline -Confirm:$false
```

## How to interpret the validator

The replacement is correctly configured when:

- The target object exists.
- The target has `RecipientTypeDetails` equal to `RoomList`.
- The target has the exact `DisplayName` users should see.
- Every intended room is a direct target member.
- The intended rooms are no longer members of the retired list.
- The retired list is either empty or absent.
- Each expected room resolves as a resource mailbox.
- No accidental duplicate building memberships remain.
- The change was made at the correct source of authority.

The script flags membership in multiple room lists for review. Microsoft permits room lists to represent buildings, floors, wings, or other logical groupings. Duplicate membership can therefore be deliberate. In an operating model where each room list represents one building, each room should normally belong to only one building room list.

---

# Create a room list

## Create a new cloud-managed room list

Edit the values first:

```powershell
$RoomListName    = "Dublin Headquarters"
$RoomListAlias   = "DublinHQRooms"
$RoomListAddress = "dublinhqrooms@contoso.com"
$Owner           = "admin@contoso.com"

New-DistributionGroup `
    -Name $RoomListName `
    -DisplayName $RoomListName `
    -Alias $RoomListAlias `
    -PrimarySmtpAddress $RoomListAddress `
    -ManagedBy $Owner `
    -RoomList
```

Immediately verify the object:

```powershell
Get-DistributionGroup -Identity $RoomListAddress |
    Format-List Name,
                DisplayName,
                Alias,
                PrimarySmtpAddress,
                RecipientTypeDetails,
                ManagedBy,
                IsDirSynced
```

Required result:

```text
RecipientTypeDetails : RoomList
```

If the result is `MailUniversalDistributionGroup`, you created an ordinary distribution group rather than a room list.

## Convert an existing distribution group into a room list

Microsoft supports converting an existing distribution group:

```powershell
Set-DistributionGroup `
    -Identity "dublinhqrooms@contoso.com" `
    -RoomList
```

Verify:

```powershell
Get-DistributionGroup -Identity "dublinhqrooms@contoso.com" |
    Format-List DisplayName,
                PrimarySmtpAddress,
                RecipientTypeDetails
```

Before converting a group, inspect its membership and remove normal users, shared mailboxes, contacts, and nested groups that do not belong in Room Finder.

---

# Add rooms to a room list

## Validate the room mailboxes first

```powershell
$Rooms = @(
    "room1@contoso.com",
    "room2@contoso.com"
)

foreach ($Room in $Rooms) {
    Get-Mailbox -Identity $Room |
        Format-List DisplayName,
                    PrimarySmtpAddress,
                    RecipientTypeDetails,
                    HiddenFromAddressListsEnabled,
                    IsDirSynced
}
```

For a normal cloud room mailbox, expect:

```text
RecipientTypeDetails : RoomMailbox
```

## Add the rooms

```powershell
$RoomList = "dublinhqrooms@contoso.com"

foreach ($Room in $Rooms) {
    Add-DistributionGroupMember `
        -Identity $RoomList `
        -Member $Room
}
```

If you are an authorised Exchange administrator but are not listed in the group's `ManagedBy` property:

```powershell
foreach ($Room in $Rooms) {
    Add-DistributionGroupMember `
        -Identity $RoomList `
        -Member $Room `
        -BypassSecurityGroupManagerCheck
}
```

## Verify the membership immediately

```powershell
Get-DistributionGroupMember `
    -Identity $RoomList `
    -ResultSize Unlimited |
    Sort-Object DisplayName |
    Format-Table DisplayName,
                 PrimarySmtpAddress,
                 RecipientTypeDetails -AutoSize
```

Adding a member succeeds when it appears in this PowerShell output. A delay in Teams or Outlook after that point is a propagation issue, not proof that the Exchange command failed.

---

# Remove rooms from a room list

```powershell
$RoomList = "oldbuildingrooms@contoso.com"

$Rooms = @(
    "room1@contoso.com",
    "room2@contoso.com"
)

foreach ($Room in $Rooms) {
    Remove-DistributionGroupMember `
        -Identity $RoomList `
        -Member $Room `
        -Confirm:$false
}
```

Use `-BypassSecurityGroupManagerCheck` when required by ownership and your assigned Exchange role:

```powershell
foreach ($Room in $Rooms) {
    Remove-DistributionGroupMember `
        -Identity $RoomList `
        -Member $Room `
        -BypassSecurityGroupManagerCheck `
        -Confirm:$false
}
```

Verify:

```powershell
Get-DistributionGroupMember `
    -Identity $RoomList `
    -ResultSize Unlimited
```

Removing a room from a room list does not delete or disable the room mailbox. It only removes that room from the logical grouping used by Room Finder.

---

# Move rooms from an old list to a new list

Use this order:

1. Confirm the new room list is a genuine `RoomList`.
2. Add the rooms to the new list.
3. Verify every room is present in the new list.
4. Remove the rooms from the old list.
5. Verify the old list is empty or contains only rooms that should remain.
6. Allow 24 to 48 hours for the client experience to converge.
7. Delete the old list only when it is no longer required.

Example:

```powershell
$OldRoomList = "oldbuildingrooms@contoso.com"
$NewRoomList = "newbuildingrooms@contoso.com"

$Rooms = @(
    "room1@contoso.com",
    "room2@contoso.com"
)

$NewListObject = Get-DistributionGroup -Identity $NewRoomList

if ($NewListObject.RecipientTypeDetails -ne "RoomList") {
    throw "$NewRoomList is not a RoomList."
}

foreach ($Room in $Rooms) {
    Add-DistributionGroupMember `
        -Identity $NewRoomList `
        -Member $Room
}

$NewMembers = Get-DistributionGroupMember `
    -Identity $NewRoomList `
    -ResultSize Unlimited

$NewMemberAddresses = @(
    $NewMembers |
        ForEach-Object {
            $_.PrimarySmtpAddress.ToString().ToLowerInvariant()
        }
)

foreach ($Room in $Rooms) {
    if ($NewMemberAddresses -notcontains $Room.ToLowerInvariant()) {
        throw "$Room was not found in the new room list."
    }
}

foreach ($Room in $Rooms) {
    Remove-DistributionGroupMember `
        -Identity $OldRoomList `
        -Member $Room `
        -Confirm:$false
}
```

A brief period of duplicate membership during a controlled move is safer than removing rooms from the old list before proving the new list is correct.

---

# Rename a room list

Use this when the same logical building or location remains and only its displayed name needs to change.

```powershell
Set-DistributionGroup `
    -Identity "buildingrooms@contoso.com" `
    -Name "Dublin Headquarters" `
    -DisplayName "Dublin Headquarters"
```

Verify:

```powershell
Get-DistributionGroup -Identity "buildingrooms@contoso.com" |
    Format-List Name,
                DisplayName,
                Alias,
                PrimarySmtpAddress,
                RecipientTypeDetails,
                WhenChangedUTC
```

The Room Finder building value should follow the room list's display name after propagation.

Renaming `Name` and `DisplayName` does not inherently require changing the primary SMTP address. Avoid changing the alias or email address unless there is a real operational requirement. Email address policies can cause an alias change to affect addresses.

---

# Delete a room list safely

## What deletion does

`Remove-DistributionGroup` deletes the room-list distribution group.

It does not delete:

- The room mailboxes that were members.
- Their calendars.
- Their booking settings.
- Their Teams Rooms resource accounts.
- Meetings already booked against the room mailboxes.

## Back up the list before deletion

```powershell
$RoomList = "oldbuildingrooms@contoso.com"
$BackupPath = "$env:USERPROFILE\Desktop\RoomListBackup"

New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null

Get-DistributionGroup -Identity $RoomList |
    Select-Object Name,
                  DisplayName,
                  Alias,
                  PrimarySmtpAddress,
                  ManagedBy,
                  RecipientTypeDetails,
                  IsDirSynced |
    Export-Csv `
        -Path "$BackupPath\RoomList.csv" `
        -NoTypeInformation `
        -Encoding UTF8

Get-DistributionGroupMember `
    -Identity $RoomList `
    -ResultSize Unlimited |
    Select-Object DisplayName,
                  PrimarySmtpAddress,
                  RecipientTypeDetails |
    Export-Csv `
        -Path "$BackupPath\RoomListMembers.csv" `
        -NoTypeInformation `
        -Encoding UTF8
```

## Confirm it is the correct object

```powershell
Get-DistributionGroup -Identity $RoomList |
    Format-List Name,
                DisplayName,
                PrimarySmtpAddress,
                RecipientTypeDetails,
                IsDirSynced

Get-DistributionGroupMember `
    -Identity $RoomList `
    -ResultSize Unlimited
```

Stop if:

- `RecipientTypeDetails` is not `RoomList`.
- `IsDirSynced` is `True` and you have not changed the authoritative on-premises object.
- The list still contains rooms that have not been moved or intentionally retired.
- The SMTP identity or display name does not match the object you intended to delete.

## Delete the list

Interactive confirmation:

```powershell
Remove-DistributionGroup -Identity $RoomList
```

Non-interactive confirmation suppression:

```powershell
Remove-DistributionGroup `
    -Identity $RoomList `
    -Confirm:$false
```

When required:

```powershell
Remove-DistributionGroup `
    -Identity $RoomList `
    -BypassSecurityGroupManagerCheck `
    -Confirm:$false
```

## Prove that it was deleted

```powershell
Get-DistributionGroup `
    -Identity $RoomList `
    -ErrorAction SilentlyContinue

Get-DistributionGroup `
    -RecipientTypeDetails RoomList `
    -ResultSize Unlimited |
    Sort-Object DisplayName |
    Format-Table DisplayName,
                 PrimarySmtpAddress,
                 IsDirSynced -AutoSize
```

The first command should return no object. The old name can still remain visible in Teams or Outlook during the documented 24-to-48-hour propagation window.

---

# Optional Room Finder metadata validation

This section does not configure Microsoft Places or Places Finder.

The `Get-Place` and `Set-Place` cmdlets are also available in Exchange Online PowerShell and are used by Microsoft to read or set Room Finder metadata on resource mailboxes. The MicrosoftPlaces module is not required.

Microsoft recommends that rooms in one room list have a consistent `City`, and that `Floor` and `Capacity` are populated for useful filtering.

Read-only check:

```powershell
$RoomList = "dublinhqrooms@contoso.com"

Get-DistributionGroupMember `
    -Identity $RoomList `
    -ResultSize Unlimited |
    ForEach-Object {
        Get-Place -Identity $_.PrimarySmtpAddress |
            Select-Object DisplayName,
                          Identity,
                          City,
                          Floor,
                          FloorLabel,
                          Capacity
    } |
    Format-Table -AutoSize
```

A city mismatch can cause a room list to appear only under the city that contains the majority of its member rooms.

Skip this section when you only need to prove that the room-list object and membership changes were successful.

---

# Client validation

Use this order after Exchange PowerShell is correct:

1. Record the time of the last successful room-list change.
2. Allow the full 24-to-48-hour propagation period.
3. Test Teams on the web.
4. Test Outlook on the web.
5. Test with at least two users.
6. Confirm the new building or room-list name appears.
7. Confirm every expected room appears under it.
8. Confirm the retired room list no longer appears.
9. Only then sign out and back in to the desktop client or clear its cache.

Testing web clients first separates server-side propagation from a stale local Teams or Outlook cache.

If only one user is affected, inspect whether that user has an Exchange Address Book Policy:

```powershell
Get-Mailbox -Identity "user@contoso.com" |
    Format-List DisplayName,
                PrimarySmtpAddress,
                AddressBookPolicy
```

An Address Book Policy or customised address-list design can make the room list or its room mailboxes visible to some users but not others.

---

# Troubleshooting matrix

| Symptom | Most likely explanation | Validation |
|---|---|---|
| The group exists but is not shown in the tenant room-list inventory | It is an ordinary distribution group | Check `RecipientTypeDetails`; convert it with `Set-DistributionGroup -RoomList` if appropriate |
| The new list appears in PowerShell but not in Teams or Outlook | Normal propagation or stale client data | Wait 24 to 48 hours, then test web clients |
| The old building still appears after deletion | Propagation is incomplete, a second similarly named room list exists, or the object was deleted at the wrong source | List every `RoomList`, check exact SMTP addresses and `IsDirSynced` |
| The new building appears but contains no rooms | The list has no direct members or members are not resource mailboxes | Run `Get-DistributionGroupMember` and inspect member types |
| A room appears under both old and new buildings | It remains a member of both lists | Build the tenant-wide membership map and remove the unintended membership |
| Some expected rooms are missing | They were not added, are hidden, have incompatible metadata, or are affected by address-list policy | Check membership, mailbox type, visibility, city consistency, and the user's Address Book Policy |
| `Add-DistributionGroupMember` or removal fails with an ownership error | The administrator is not a group owner | Use an authorised account or `-BypassSecurityGroupManagerCheck` with the required Exchange role |
| A cloud-side change fails or later reverts | The object is directory-synchronised | Check `IsDirSynced` and modify the on-premises source |
| The list name changed but its SMTP address did not | This is normal | Room Finder uses the display name; change the address only when required |
| Deleting the list did not delete the rooms | This is expected | `Remove-DistributionGroup` removes the group, not its member mailboxes |
| Teams desktop differs from Teams web | Local cache or sign-in state | Trust server-side PowerShell and web-client results first |
| The issue remains after 48 hours and web clients are still wrong | Service-side indexing or tenant-specific issue | Capture audit output and open a Microsoft support case |

---

# Common mistakes

## Creating a normal distribution group

Incorrect result:

```text
RecipientTypeDetails : MailUniversalDistributionGroup
```

Correct result:

```text
RecipientTypeDetails : RoomList
```

Fix:

```powershell
Set-DistributionGroup `
    -Identity "buildingrooms@contoso.com" `
    -RoomList
```

## Adding the room list to another group instead of adding rooms directly

Room Finder should receive direct room or workspace mailbox members. Avoid relying on nested distribution groups.

## Removing rooms before proving the replacement list

Add and verify the new membership first. Then remove the old membership.

## Deleting the old list immediately after making the change

PowerShell can be correct while clients still show cached or indexed data. Deletion does not force immediate Room Finder refresh.

## Using a display name as the only identity

Display names are not guaranteed to be unique. Use the room list's primary SMTP address for changes and deletion.

## Changing a synchronised object in the cloud

Check `IsDirSynced` before every destructive operation.

## Treating a Teams Rooms resource account as the room list

The resource account is the bookable room mailbox. The room list is the Exchange distribution group that contains resource mailboxes.

## Assuming the Teams client is authoritative

Exchange Online PowerShell is the authoritative validation point for the object type and direct membership.

---

# Change checklist

## Before the change

- [ ] Record the old and new room-list SMTP addresses.
- [ ] Confirm whether each object is cloud-managed or synchronised.
- [ ] Export the old list and its members.
- [ ] Confirm the replacement object is a genuine `RoomList`.
- [ ] Confirm every intended member is a room or workspace resource mailbox.
- [ ] Record the current room-list inventory.
- [ ] Record any Address Book Policy used by test users.

## During the change

- [ ] Add rooms to the new list.
- [ ] Verify the new membership in PowerShell.
- [ ] Remove rooms from the old list.
- [ ] Verify the old list is empty or contains only intended rooms.
- [ ] Run the comprehensive validator.
- [ ] Record `WhenChangedUTC`.

## Before deleting the old list

- [ ] Confirm the exact SMTP identity.
- [ ] Confirm `RecipientTypeDetails` is `RoomList`.
- [ ] Confirm `IsDirSynced` is appropriate for the management path.
- [ ] Confirm no required rooms remain.
- [ ] Confirm a backup export exists.
- [ ] Confirm the replacement list is complete.

## After the change

- [ ] Prove the old object is absent or intentionally retained.
- [ ] Prove the new object and members are correct.
- [ ] Allow 24 to 48 hours.
- [ ] Test Teams web and Outlook web.
- [ ] Test with more than one user.
- [ ] Troubleshoot desktop cache only after web clients are correct.
- [ ] Escalate to Microsoft with audit output if web clients remain wrong after the propagation window.

---

# Recommended operating model

- Use one room list per building when the Building filter should represent physical buildings.
- Use a clear, user-facing `DisplayName`.
- Use the primary SMTP address as the administrative identity in scripts.
- Keep direct membership authoritative and documented.
- Avoid normal user, shared mailbox, contact, and nested-group members.
- Keep rooms in the same list geographically coherent.
- Keep each building room in one building room list unless duplicate membership is intentional.
- Export membership before destructive changes.
- Validate in Exchange Online before waiting for clients.
- Treat 24 to 48 hours as the normal Room Finder propagation window.

---

# Microsoft documentation

- [Configure rooms and workspaces for Room Finder](https://learn.microsoft.com/en-us/microsoft-365-apps/outlook/calendaring/configure-room-finder-rooms-workspaces)
- [Connect-ExchangeOnline](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/connect-exchangeonline?view=exchange-ps)
- [New-DistributionGroup](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-distributiongroup?view=exchange-ps)
- [Set-DistributionGroup](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/set-distributiongroup?view=exchange-ps)
- [Get-DistributionGroup](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-distributiongroup?view=exchange-ps)
- [Remove-DistributionGroup](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/remove-distributiongroup?view=exchange-ps)
- [Add-DistributionGroupMember](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/add-distributiongroupmember?view=exchange-ps)
- [Remove-DistributionGroupMember](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/remove-distributiongroupmember?view=exchange-ps)
- [Get-DistributionGroupMember](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-distributiongroupmember?view=exchange-ps)
