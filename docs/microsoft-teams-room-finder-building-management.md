# Microsoft Teams and Outlook Room Finder Building Management

**Last updated:** 10 July 2026  
**Applies to:** Exchange Online, Microsoft Teams, Outlook Room Finder, Microsoft Places and Places Finder

## Purpose

Use this guide when you need to remove an old building from the room-selection experience, add a replacement building, move rooms between buildings, or diagnose why a building change has not appeared in Teams or Outlook.

The most important point is that Microsoft currently has two different room-browsing models:

| Experience | What users browse | What controls the displayed building |
|---|---|---|
| **Room Finder** | Exchange room lists | The display name of an Exchange distribution group whose `RecipientTypeDetails` is `RoomList` |
| **Places Finder** | Microsoft Places hierarchy | A Microsoft Places `Building` object containing floors and rooms/workspaces |

A change made only with `Set-Place -Building` does **not** change the building displayed in classic Room Finder. Room Finder displays Exchange room lists as buildings.

For Places Finder, the deprecated room-level `Building` property is not the authoritative hierarchy. A room must be parented to a floor or section, and that floor must be parented to the intended building.

## Expected propagation

Do not treat several hours of delay as proof that the configuration failed.

- Exchange Room Finder changes can take **24 to 48 hours** to appear.
- New Places building, floor and section objects should normally appear quickly.
- Changes to Places room and workspace associations can take **up to 24 hours**.
- A user sees either Room Finder or Places Finder according to the tenant's Places Finder settings; they do not see both experiences at the same time.

Always confirm the server-side configuration before troubleshooting a Teams desktop cache.

---

## Prerequisites

Run PowerShell 7 as an administrator.

Required modules:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
Install-Module MicrosoftPlaces -Scope CurrentUser -Force
```

Typical roles:

- Exchange Administrator for Exchange room lists and room mailbox configuration.
- Exchange Administrator, Global Administrator, Place Administrator, or an appropriate Microsoft Places management role for Places hierarchy changes, depending on the operation.

In a hybrid or directory-synchronised environment, check `IsDirSynced` before changing an object. A synchronised room list or room mailbox may need to be changed in the on-premises source of authority.

---

# Part 1: Read-only end-to-end audit

Edit only the variables at the top. The audit does not modify Exchange Online or Microsoft Places.

```powershell
#requires -Version 7.0

# ============================================================
# EDIT THESE VALUES
# ============================================================

$OldBuildingName = "Old Building Name"
$NewBuildingName = "New Building Name"

# Add every room that should appear under the replacement building.
# Leave as an empty array if you only want to inspect the environment.
$ExpectedRooms = @(
    "room1@contoso.com",
    "room2@contoso.com"
)

# Optional user who is testing the Teams or Outlook picker.
# Leave blank to skip the user-specific checks.
$TestUser = "user@contoso.com"

# ============================================================
# EXCHANGE ONLINE: CLASSIC ROOM FINDER
# ============================================================

Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline -ShowBanner:$false

Write-Host "`n=== ALL EXCHANGE ROOM LISTS ===" -ForegroundColor Cyan

$RoomLists = Get-DistributionGroup -ResultSize Unlimited |
    Where-Object RecipientTypeDetails -eq "RoomList"

$RoomLists |
    Sort-Object DisplayName |
    Select-Object DisplayName,
                  Name,
                  Alias,
                  PrimarySmtpAddress,
                  RecipientTypeDetails,
                  HiddenFromAddressListsEnabled,
                  IsDirSynced,
                  WhenChangedUTC |
    Format-Table -AutoSize

function Find-RoomList {
    param(
        [Parameter(Mandatory)]
        [string]$SearchValue,

        [Parameter(Mandatory)]
        [array]$RoomListCollection
    )

    $RoomListCollection | Where-Object {
        $_.DisplayName -eq $SearchValue -or
        $_.Name -eq $SearchValue -or
        $_.Alias -eq $SearchValue -or
        $_.PrimarySmtpAddress.ToString() -eq $SearchValue
    }
}

$OldRoomList = Find-RoomList -SearchValue $OldBuildingName -RoomListCollection $RoomLists
$NewRoomList = Find-RoomList -SearchValue $NewBuildingName -RoomListCollection $RoomLists

Write-Host "`n=== OLD ROOM LIST MATCH ===" -ForegroundColor Cyan

if ($OldRoomList) {
    $OldRoomList |
        Format-List Name,
                    DisplayName,
                    Alias,
                    PrimarySmtpAddress,
                    RecipientTypeDetails,
                    HiddenFromAddressListsEnabled,
                    IsDirSynced,
                    WhenChangedUTC
}
else {
    Write-Host "No old Exchange Room List was found."
}

Write-Host "`n=== NEW ROOM LIST MATCH ===" -ForegroundColor Cyan

if ($NewRoomList) {
    $NewRoomList |
        Format-List Name,
                    DisplayName,
                    Alias,
                    PrimarySmtpAddress,
                    RecipientTypeDetails,
                    HiddenFromAddressListsEnabled,
                    IsDirSynced,
                    WhenChangedUTC
}
else {
    Write-Warning "No new Exchange Room List was found."
}

Write-Host "`n=== ALL ROOM LIST MEMBERSHIPS ===" -ForegroundColor Cyan

$AllMemberships = foreach ($RoomList in $RoomLists) {
    $Members = Get-DistributionGroupMember `
        -Identity $RoomList.PrimarySmtpAddress `
        -ResultSize Unlimited `
        -ErrorAction SilentlyContinue

    foreach ($Member in $Members) {
        [pscustomobject]@{
            RoomListDisplayName = $RoomList.DisplayName
            RoomListSmtpAddress = $RoomList.PrimarySmtpAddress.ToString()
            MemberDisplayName   = $Member.DisplayName
            MemberSmtpAddress   = $Member.PrimarySmtpAddress.ToString()
            MemberType          = $Member.RecipientTypeDetails
        }
    }
}

$AllMemberships |
    Sort-Object RoomListDisplayName, MemberDisplayName |
    Format-Table -AutoSize

Write-Host "`n=== EXPECTED ROOM MEMBERSHIP ===" -ForegroundColor Cyan

foreach ($ExpectedRoom in $ExpectedRooms) {
    $Matches = $AllMemberships |
        Where-Object MemberSmtpAddress -eq $ExpectedRoom

    if (-not $Matches) {
        Write-Warning "$ExpectedRoom is not a member of any Room List."
    }
    else {
        $Matches |
            Select-Object MemberSmtpAddress,
                          RoomListDisplayName,
                          RoomListSmtpAddress,
                          MemberType |
            Format-Table -AutoSize
    }
}

Write-Host "`n=== ROOMS IN MULTIPLE ROOM LISTS ===" -ForegroundColor Cyan

$DuplicateMemberships = $AllMemberships |
    Group-Object MemberSmtpAddress |
    Where-Object Count -gt 1

if ($DuplicateMemberships) {
    foreach ($Duplicate in $DuplicateMemberships) {
        Write-Warning "$($Duplicate.Name) belongs to more than one Room List:"
        $Duplicate.Group |
            Select-Object RoomListDisplayName, RoomListSmtpAddress |
            Format-Table -AutoSize
    }
}
else {
    Write-Host "No duplicate Room List memberships were found."
}

Write-Host "`n=== TARGET ROOM MAILBOX AND PLACE PROPERTIES ===" -ForegroundColor Cyan

$RoomsToInspect = @(
    $ExpectedRooms
    if ($OldRoomList) {
        (Get-DistributionGroupMember -Identity $OldRoomList.PrimarySmtpAddress -ResultSize Unlimited).PrimarySmtpAddress
    }
    if ($NewRoomList) {
        (Get-DistributionGroupMember -Identity $NewRoomList.PrimarySmtpAddress -ResultSize Unlimited).PrimarySmtpAddress
    }
) |
    Where-Object { $_ } |
    ForEach-Object { $_.ToString().ToLowerInvariant() } |
    Sort-Object -Unique

$RoomAudit = foreach ($RoomAddress in $RoomsToInspect) {
    try {
        $Mailbox = Get-Mailbox -Identity $RoomAddress -ErrorAction Stop
        $Place = Get-Place -Identity $RoomAddress -ErrorAction Stop

        [pscustomobject]@{
            DisplayName       = $Mailbox.DisplayName
            SmtpAddress       = $Mailbox.PrimarySmtpAddress
            RecipientType     = $Mailbox.RecipientTypeDetails
            HiddenFromGAL     = $Mailbox.HiddenFromAddressListsEnabled
            IsDirSynced       = $Mailbox.IsDirSynced
            City              = $Place.City
            BuildingProperty  = $Place.Building
            Floor             = $Place.Floor
            FloorLabel        = $Place.FloorLabel
            Capacity          = $Place.Capacity
            MTREnabled        = $Place.MTREnabled
        }
    }
    catch {
        [pscustomobject]@{
            DisplayName       = "Unable to read"
            SmtpAddress       = $RoomAddress
            RecipientType     = "Unable to read"
            HiddenFromGAL     = "Unable to read"
            IsDirSynced       = "Unable to read"
            City              = "Unable to read"
            BuildingProperty  = "Unable to read"
            Floor             = "Unable to read"
            FloorLabel        = "Unable to read"
            Capacity          = "Unable to read"
            MTREnabled        = "Unable to read"
        }
    }
}

$RoomAudit | Format-Table -AutoSize

if ($TestUser) {
    Write-Host "`n=== TEST USER EXCHANGE SETTINGS ===" -ForegroundColor Cyan

    Get-Mailbox -Identity $TestUser |
        Select-Object DisplayName,
                      PrimarySmtpAddress,
                      AddressBookPolicy |
        Format-List
}

# ============================================================
# MICROSOFT PLACES: PLACES FINDER
# ============================================================

Import-Module MicrosoftPlaces
Connect-MicrosoftPlaces

Write-Host "`n=== MICROSOFT PLACES SETTINGS ===" -ForegroundColor Cyan
Get-PlacesSettings | Format-List *

Write-Host "`n=== ALL MICROSOFT PLACES BUILDINGS ===" -ForegroundColor Cyan

$PlacesBuildings = Get-PlaceV3 -Type Building

$PlacesBuildings |
    Sort-Object DisplayName |
    Select-Object DisplayName,
                  PlaceId,
                  City,
                  State,
                  CountryOrRegion |
    Format-Table -AutoSize

$OldPlacesBuilding = $PlacesBuildings |
    Where-Object DisplayName -eq $OldBuildingName

$NewPlacesBuilding = $PlacesBuildings |
    Where-Object DisplayName -eq $NewBuildingName

Write-Host "`n=== OLD PLACES BUILDING ===" -ForegroundColor Cyan

if ($OldPlacesBuilding) {
    $OldPlacesBuilding | Format-List *

    Write-Host "`nObjects underneath the old Places building:" -ForegroundColor Cyan

    Get-PlaceV3 -AncestorId $OldPlacesBuilding.PlaceId |
        Select-Object DisplayName,
                      Type,
                      PlaceId,
                      ParentId,
                      Mailbox |
        Format-Table -AutoSize
}
else {
    Write-Host "No old Microsoft Places building was found."
}

Write-Host "`n=== NEW PLACES BUILDING ===" -ForegroundColor Cyan

if ($NewPlacesBuilding) {
    $NewPlacesBuilding | Format-List *

    Write-Host "`nObjects underneath the new Places building:" -ForegroundColor Cyan

    Get-PlaceV3 -AncestorId $NewPlacesBuilding.PlaceId |
        Select-Object DisplayName,
                      Type,
                      PlaceId,
                      ParentId,
                      Mailbox |
        Format-Table -AutoSize
}
else {
    Write-Warning "No new Microsoft Places building was found."
}

Write-Host "`n=== EXPECTED ROOM PLACES OBJECTS ===" -ForegroundColor Cyan

foreach ($ExpectedRoom in $ExpectedRooms) {
    try {
        Get-PlaceV3 -Identity $ExpectedRoom -ErrorAction Stop |
            Select-Object DisplayName,
                          Type,
                          PlaceId,
                          ParentId,
                          Mailbox,
                          Capacity |
            Format-List
    }
    catch {
        Write-Warning "No Microsoft Places room object was found for $ExpectedRoom."
    }
}
```

---

# Part 2: Interpret the audit

## A. Classic Room Finder is correct when

- The replacement object exists as an Exchange distribution group.
- `RecipientTypeDetails` is exactly `RoomList`.
- Its `DisplayName` is exactly the building name users should see.
- Every intended room or workspace is a member of that room list.
- The rooms are no longer members of the retired building's room list.
- No room is accidentally a member of multiple building room lists.
- Each member is a room or workspace mailbox, not a normal user or shared mailbox.
- `HiddenFromAddressListsEnabled` is `False` for rooms that should be discoverable.
- `City` is populated and consistent across the members of a room list.
- `Floor`, `FloorLabel` and `Capacity` are populated where applicable.
- The room list and rooms were changed at the correct source of authority.
- Any Address Book Policy applied to the test user allows the room list and rooms to be resolved.

Room Finder displays the **room list's display name** as the building. It does not use the room mailbox's `Building` property to populate the building picker.

Microsoft recommends one room list per building when Room Finder and Places Finder are maintained in parallel. A Room Finder search returns no more than 100 spaces, and Microsoft recommends limiting a room list to approximately 50 rooms/workspaces for optimal performance.

## B. Places Finder is correct when

- `Get-PlacesSettings` shows that Places Finder is enabled for the affected user population.
- Building visibility is enabled with `EnableBuildings` where required.
- The new building appears in `Get-PlaceV3 -Type Building`.
- The building contains at least one floor.
- Rooms are parented to a floor or an optional section below the intended building.
- Workspaces are parented to a section; a workspace should not be parented directly to a floor.
- Each room's `ParentId` points to the correct floor or section.
- The old building has no remaining rooms, workspaces, sections or floors that still need to be retained or moved.

The authoritative Places hierarchy is:

```text
Building
└── Floor
    ├── Section, where required or desired
    │   ├── Workspace
    │   └── Room, optional
    └── Room
```

Once a room is linked into this hierarchy, building address information should be managed on the building object. The room-level `Building` parameter is deprecated for hierarchy purposes.

---

# Part 3: Correct classic Room Finder

## Option 1: Rename the existing building

Use this when the physical building and its room membership remain the same and only the displayed name is changing.

```powershell
Connect-ExchangeOnline

Set-DistributionGroup `
    -Identity "oldbuildingrooms@contoso.com" `
    -Name "New Building Name" `
    -DisplayName "New Building Name"
```

Verify:

```powershell
Get-DistributionGroup -Identity "oldbuildingrooms@contoso.com" |
    Format-List Name, DisplayName, PrimarySmtpAddress, RecipientTypeDetails, IsDirSynced
```

Renaming the group does not necessarily change its primary SMTP address, which is normally acceptable. Change the address only if your organisation requires it and you have assessed dependencies.

## Option 2: Create a replacement Room List

Use this when the new building is a separate physical location or when you intentionally want a new Room List object.

```powershell
Connect-ExchangeOnline

New-DistributionGroup `
    -Name "New Building Name" `
    -DisplayName "New Building Name" `
    -Alias "NewBuildingRooms" `
    -PrimarySmtpAddress "newbuildingrooms@contoso.com" `
    -RoomList
```

Verify that it is a genuine Room List:

```powershell
Get-DistributionGroup -Identity "newbuildingrooms@contoso.com" |
    Format-List Name, DisplayName, PrimarySmtpAddress, RecipientTypeDetails
```

Expected result:

```text
RecipientTypeDetails : RoomList
```

An ordinary distribution group is not sufficient.

## Add rooms to the new Room List

```powershell
$Rooms = @(
    "room1@contoso.com",
    "room2@contoso.com"
)

foreach ($Room in $Rooms) {
    Add-DistributionGroupMember `
        -Identity "newbuildingrooms@contoso.com" `
        -Member $Room
}
```

Verify immediately:

```powershell
Get-DistributionGroupMember `
    -Identity "newbuildingrooms@contoso.com" `
    -ResultSize Unlimited |
    Format-Table DisplayName, PrimarySmtpAddress, RecipientTypeDetails
```

## Remove rooms from the old Room List

```powershell
foreach ($Room in $Rooms) {
    Remove-DistributionGroupMember `
        -Identity "oldbuildingrooms@contoso.com" `
        -Member $Room `
        -Confirm:$false
}
```

Verify that each room belongs only to the intended building Room List.

## Delete the retired Room List

Delete the old Room List only after confirming that no rooms or workspaces still require it.

```powershell
Get-DistributionGroupMember `
    -Identity "oldbuildingrooms@contoso.com" `
    -ResultSize Unlimited

Remove-DistributionGroup `
    -Identity "oldbuildingrooms@contoso.com"
```

This deletes the Room List distribution group. It does not delete the room mailboxes that were members of the group.

## Hybrid warning

When `IsDirSynced` is `True`, do not assume the cloud object is writable. Microsoft documents that hybrid room lists should be created and managed on-premises and synchronised to Exchange Online. Make the change at the authoritative on-premises object and allow directory synchronisation to complete.

---

# Part 4: Correct Microsoft Places and Places Finder

## Connect and inspect settings

```powershell
Install-Module MicrosoftPlaces -Scope CurrentUser -Force
Import-Module MicrosoftPlaces
Connect-MicrosoftPlaces

Get-PlacesSettings | Format-List *
```

Where required, enable building visibility:

```powershell
Set-PlacesSettings -EnableBuildings 'Default:true'
```

Places Finder can be enabled tenant-wide with:

```powershell
Set-PlacesSettings -PlacesFinderEnabled 'Default:true'
```

Use a controlled pilot rather than enabling it globally when the hierarchy has not yet been validated for every building. For group-scoped enablement, Microsoft requires a mail-enabled security group.

## Rename an existing Places building

Use the building's `PlaceId` rather than a room mailbox address.

```powershell
$Building = Get-PlaceV3 -Type Building |
    Where-Object DisplayName -eq "Old Building Name"

Set-PlaceV3 `
    -Identity $Building.PlaceId `
    -DisplayName "New Building Name"
```

When Room Finder is also in use, rename the corresponding Exchange Room List so both experiences remain consistent.

## Create the new building

```powershell
$NewBuilding = New-Place `
    -Type Building `
    -Name "New Building Name"
```

Add building-level metadata:

```powershell
Set-PlaceV3 `
    -Identity $NewBuilding.PlaceId `
    -CountryOrRegion "IE" `
    -State "County" `
    -City "City" `
    -Street "Street address" `
    -PostalCode "Postal code"
```

## Create a floor

```powershell
$NewFloor = New-Place `
    -Type Floor `
    -Name "1" `
    -ParentId $NewBuilding.PlaceId
```

A room may be parented directly to a floor or to a section under a floor.

## Optional: Create a section

A workspace must be parented to a section. Sections can also be used to organise rooms.

```powershell
$NewSection = New-Place `
    -Type Section `
    -Name "North Wing" `
    -ParentId $NewFloor.PlaceId
```

## Move rooms to the new building hierarchy

Parent each room to the intended floor or section:

```powershell
$Rooms = @(
    "room1@contoso.com",
    "room2@contoso.com"
)

foreach ($Room in $Rooms) {
    Set-PlaceV3 `
        -Identity $Room `
        -ParentId $NewFloor.PlaceId
}
```

Moving a room by changing its `ParentId` dissociates it from the previous Places hierarchy.

For a workspace, use a section as the parent:

```powershell
Set-PlaceV3 `
    -Identity "workspace1@contoso.com" `
    -ParentId $NewSection.PlaceId
```

## Verify the new hierarchy

```powershell
Get-PlaceV3 -Identity "room1@contoso.com" |
    Format-List DisplayName, Type, PlaceId, ParentId, Mailbox

Get-PlaceV3 -AncestorId $NewBuilding.PlaceId |
    Format-Table DisplayName, Type, PlaceId, ParentId, Mailbox
```

Do not use only this legacy command and expect Places Finder hierarchy to change:

```powershell
Set-Place -Identity "room1@contoso.com" -Building "New Building Name"
```

That property remains useful for compatibility in some scenarios, but it does not replace the Places building, floor and parent relationship.

---

# Part 5: Safely remove the old Places building

First inspect every descendant:

```powershell
$OldBuilding = Get-PlaceV3 -Type Building |
    Where-Object DisplayName -eq "Old Building Name"

Get-PlaceV3 -AncestorId $OldBuilding.PlaceId |
    Format-Table DisplayName, Type, PlaceId, ParentId, Mailbox
```

Before removing the building:

1. Re-parent every retained room to a floor or section in the new building.
2. Re-parent every retained workspace to a section in the new building.
3. Confirm that no desks or other retained child objects remain.
4. Remove empty sections.
5. Remove empty floors.
6. Remove the empty building.

Example removal of an empty section, floor and building:

```powershell
Remove-Place -Identity $OldSection.PlaceId
Remove-Place -Identity $OldFloor.PlaceId
Remove-Place -Identity $OldBuilding.PlaceId
```

## Critical mailbox warning

Do **not** use `Remove-Place` against a room or workspace merely to move it.

Microsoft documents that removing a Places object associated with a mailbox automatically soft-deletes the associated mailbox. The mailbox remains soft-deleted for 30 days before permanent deletion. Relocate rooms and workspaces with `Set-PlaceV3 -ParentId` instead.

Microsoft Places also prevents removal of a parent object while child objects remain beneath it.

---

# Part 6: Final validation and client testing

Use this order:

1. Run the audit and confirm that the PowerShell objects are correct immediately.
2. Confirm whether the test user is receiving Room Finder or Places Finder through `Get-PlacesSettings`.
3. For Room Finder, allow the full **24 to 48 hours** from the last Exchange Room List modification.
4. For Places room associations, allow **up to 24 hours**.
5. Test in Teams on the web and Outlook on the web first.
6. Test with at least two users to distinguish tenant data from a user-specific policy or cache issue.
7. Confirm that the old building is absent and the new building contains the expected rooms.
8. Only after web clients show the correct server state, sign out and back in to the desktop client or reset the Teams application cache.
9. If web clients remain incorrect after the documented propagation period, capture the audit output and open a Microsoft support case.

## Useful result matrix

| Result | Likely cause |
|---|---|
| PowerShell shows the new Room List but Room Finder does not | Normal 24–48-hour Room Finder propagation, Address Book Policy visibility, or stale client state |
| `Set-Place -Building` is correct but Room Finder still shows the old building | Room Finder is controlled by Exchange Room Lists, not the room's Building property |
| New group exists but `RecipientTypeDetails` is not `RoomList` | An ordinary distribution group was created |
| Room appears in both old and new buildings in Room Finder | The room remains a member of multiple Room Lists |
| Places building exists but contains no rooms | Rooms were not parented to its floor or section using `Set-PlaceV3 -ParentId` |
| Room Finder is correct for some users but Places Finder appears for others | Places Finder is enabled only for a subset of users |
| Room is missing from both experiences | Hidden from address lists, wrong mailbox type, policy visibility, missing room-list membership, or missing Places parent hierarchy |
| Cloud command fails or changes revert | Object is directory-synchronised and must be changed on-premises |
| New Places building appears but moved rooms do not | Room/workspace association propagation can take up to 24 hours |

---

# Recommended operating model

To keep the two Microsoft experiences aligned:

- Maintain one Exchange Room List per physical building.
- Give the Room List the exact same display name as the Microsoft Places building.
- Add each room to only its correct building Room List.
- Parent each room to the correct Places floor or section.
- Parent workspaces to sections.
- Maintain building address metadata on the Places building.
- Maintain capacity and equipment metadata on the room or workspace.
- Update both the Exchange Room List and Places hierarchy whenever a room moves building.
- Validate with PowerShell before waiting for client propagation.

---

# Microsoft documentation

- [Configure rooms and workspaces for Room Finder](https://learn.microsoft.com/en-us/microsoft-365-apps/outlook/calendaring/configure-room-finder-rooms-workspaces)
- [Enable Places Finder](https://learn.microsoft.com/en-us/microsoft-365/places/enable-places-finder)
- [Configure buildings and floors](https://learn.microsoft.com/en-us/microsoft-365/places/get-started/quick-setup-buildings-floors)
- [Set-PlaceV3](https://learn.microsoft.com/en-us/microsoft-365/places/powershell/set-placev3)
- [Remove-Place](https://learn.microsoft.com/en-us/microsoft-365/places/powershell/remove-place)
- [Clear the Teams client cache](https://learn.microsoft.com/en-us/troubleshoot/microsoftteams/teams-administration/clear-teams-cache)
