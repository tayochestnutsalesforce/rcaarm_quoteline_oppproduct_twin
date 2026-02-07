# rcaarm_quoteline_oppproduct_twin

Pre-Built flow and LWC to manage twin fields between quote line item and opportunity product for Core Quote Object.

# Quote to Opportunity Sync

Admin-managed field mappings from Quote Line Item to Opportunity Line Item, with Flow-driven sync.

## Install / Setup

1. Deploy metadata in this repo to your org.
2. Assign the permission set `TwinFieldMapConfig_Admin` to admins who manage mappings.
3. Activate the prebuilt flows:
   - `RCA_Quote_Line_Item_to_Opportunity_Product`
   - `RCA_Sync_Quote_Line_to_Opportunity_Product`

## Flows

### `RCA_Quote_Line_Item_to_Opportunity_Product`
Purpose: mapping manager UI for admins.

- Presents the `twinFieldMappingManager` LWC to add/edit mapping rows.
- On Next/Finish, passes JSON to the reconcile invocable to upsert/delete
  `TwinFieldMapConfig__c`.

### `RCA_Sync_Quote_Line_to_Opportunity_Product`
Purpose: data sync from Quote Line Item to Opportunity Line Item.

- Runs the sync logic that applies mappings and updates OLIs using
  `QLI.OpportunityLineItemId` as the match key.

## LWC: `twinFieldMappingManager`

Purpose: manage mapping rows in a repeater‑style UI.

Inputs (Flow Screen):
- `useProvidedMappings` (Boolean): when true, uses `mappingsJson` instead of querying.
- `mappingsJson` (String): JSON array of mapping rows to prepopulate.
- `useSessionDraft` (Boolean): optional draft persistence in session storage.

Outputs:
- `mappingsOutputJson` (String): JSON array of current rows.
- `deletedIdsJson` (String): JSON array of deleted record Ids.

## Permission Set

`TwinFieldMapConfig_Admin` grants CRUD + View All + Modify All for
`TwinFieldMapConfig__c`.
