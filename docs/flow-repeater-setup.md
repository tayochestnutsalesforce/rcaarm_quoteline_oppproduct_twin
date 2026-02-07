# Flow Repeater Setup (TwinFieldMapConfig)

This project includes Apex actions to power a Screen Flow Repeater UI for `TwinFieldMapConfig__c`.

## Apex Actions Available
- **Get Mapping Flow Data** (`TwinFieldFlowDataInvocable.getFlowData`)
- **Reconcile Mapping Rows** (`TwinFieldFlowReconcileInvocable.reconcile`)

## Flow Types
- `TwinFieldFlowChoice`
- `TwinFieldFlowMappingRow`

## Suggested Flow Build (Screen Flow)
1. **Create a new Screen Flow** named `Twin Field Map Config Manager`.
2. **Add an Apex action** at the top of the flow to load Flow data:
   - Use **Get Mapping Flow Data** and store the output.
3. **Create a Screen** with the **TwinFieldMappingManager** LWC.
   - Pass `mappingsJson` from the Apex output mapping rows.
4. **On Next**, call **Reconcile Mapping Rows** and pass:
   - `mappingsJson` = LWC `mappingsOutputJson`
   - `deletedIdsJson` = LWC `deletedIdsJson`
5. **Use the status output** from the reconcile step to show success or error messaging.

## Notes
- The Apex action validates source/target and data type compatibility before saving.
- If you want the flow available in the UI, add it to a Lightning App page or a utility bar item.
