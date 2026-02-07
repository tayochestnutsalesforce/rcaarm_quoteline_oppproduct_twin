import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFieldOptions from '@salesforce/apex/TwinFieldMappingController.getFieldOptions';
import getMappings from '@salesforce/apex/TwinFieldMappingController.getMappings';

const DEFAULT_OVERWRITE_RULE = 'Always';
const DEFAULT_TRANSFORM = 'None';

export default class TwinFieldMappingManager extends LightningElement {
    @track mappings = [];
    @track sourceFieldOptions = [];
    @track targetFieldOptions = [];
    @track isLoading = false;
    @api useProvidedMappings = false;
    _providedMappings = null;
    _mappingsJson = null;
    @api mappingsOutputJson;
    @api deletedIdsJson;
    deletedIds = [];
    hasSaved = false;
    @api useSessionDraft = false;
    sourceTypeMap = {};
    targetTypeMap = {};

    @api
    get mappingsInput() {
        return this._providedMappings;
    }
    set mappingsInput(value) {
        this._providedMappings = Array.isArray(value) ? value : null;
        if (this._providedMappings) {
            this.useProvidedMappings = true;
        }
        if (this._providedMappings) {
            this.mappings = this._providedMappings.map((record) =>
                this.mapRecord(record)
            );
            this.syncOutputs();
        }
    }

    @api
    get mappingsJson() {
        return this._mappingsJson;
    }
    set mappingsJson(value) {
        this._mappingsJson = value;
        if (!value) {
            return;
        }
        try {
            const parsed = JSON.parse(value);
            if (Array.isArray(parsed)) {
                this._providedMappings = parsed;
                this.useProvidedMappings = true;
                this.mappings = parsed.map((record) => this.mapRecord(record));
                this.syncOutputs();
            }
        } catch (error) {
            this.showToast('Error', 'Invalid mappings JSON input.', 'error');
        }
    }

    overwriteRuleOptions = [
        { label: 'Always', value: 'Always' },
        { label: 'Only if target blank', value: 'OnlyIfTargetBlank' },
        { label: 'Only if source not null', value: 'OnlyIfSourceNotNull' }
    ];

    transformOptions = [
        { label: 'None', value: 'None' },
        { label: 'Round (0 decimals)', value: 'Round0' },
        { label: 'Round (2 decimals)', value: 'Round2' },
        { label: 'Default to 0', value: 'DefaultZero' }
    ];

    connectedCallback() {
        this.restoreDraftFromSession();
        this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        try {
            const shouldUseProvided =
                this.useProvidedMappings ||
                (this._providedMappings && this._providedMappings.length);
            const [fieldOptions, mappings] = await Promise.all([
                getFieldOptions(),
                shouldUseProvided ? Promise.resolve(null) : getMappings()
            ]);

            this.sourceFieldOptions = fieldOptions.sourceFields.map((field) => ({
                label: field.label,
                value: field.apiName
            }));
            this.targetFieldOptions = fieldOptions.targetFields.map((field) => ({
                label: field.label,
                value: field.apiName
            }));
            this.sourceTypeMap = this.buildTypeMap(fieldOptions.sourceFields);
            this.targetTypeMap = this.buildTypeMap(fieldOptions.targetFields);

            if (!shouldUseProvided) {
                this.mappings = mappings.map((record) => this.mapRecord(record));
                this.deletedIds = [];
                this.syncOutputs();
            } else if (this._providedMappings && this._providedMappings.length) {
                this.mappings = this._providedMappings.map((record) =>
                    this.mapRecord(record)
                );
                this.syncOutputs();
            }
        } catch (error) {
            this.showToast('Error', this.normalizeError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleAddRow() {
        const newRow = {
            key: `new-${Date.now()}`,
            id: null,
            label: '',
            sourceField: '',
            targetField: '',
            overwriteRule: DEFAULT_OVERWRITE_RULE,
            transform: DEFAULT_TRANSFORM,
            isActive: true,
            isNew: true
        };
        this.mappings = [...this.mappings, newRow];
        this.hasSaved = false;
        this.syncOutputs();
    }

    handleRemoveRow(event) {
        const index = Number(event.currentTarget.dataset.index);
        const row = this.mappings[index];
        if (row && row.id) {
            this.deletedIds = [...this.deletedIds, row.id];
        }
        this.mappings = this.mappings.filter((_, rowIndex) => rowIndex !== index);
        this.hasSaved = false;
        this.syncOutputs();
    }

    handleFieldChange(event) {
        const dataset = event.currentTarget?.dataset || event.target?.dataset || {};
        const index = Number(dataset.index);
        const field = dataset.field || event.target?.name;
        const value =
            event.detail && event.detail.value !== undefined
                ? event.detail.value
                : event.target.value;

        if (Number.isNaN(index) || !field) {
            return;
        }

        this.mappings = this.mappings.map((row, rowIndex) => {
            if (rowIndex !== index) {
                return row;
            }
            return { ...row, [field]: value };
        });
        this.hasSaved = false;
        this.syncOutputs();
    }

    handleToggleChange(event) {
        const dataset = event.currentTarget?.dataset || event.target?.dataset || {};
        const index = Number(dataset.index);
        const field = dataset.field || event.target?.name;
        const value = event.target.checked;

        if (Number.isNaN(index) || !field) {
            return;
        }

        this.mappings = this.mappings.map((row, rowIndex) => {
            if (rowIndex !== index) {
                return row;
            }
            return { ...row, [field]: value };
        });
        this.hasSaved = false;
        this.syncOutputs();
    }

    async handleSave() {
        this.isLoading = true;
        try {
            this.mergeUiValues();
            const payload = this.mappings.map((row) => ({
                id: row.id,
                label: row.label,
                sourceField: row.sourceField,
                targetField: row.targetField,
                overwriteRule: row.overwriteRule,
                transform: row.transform,
                isActive: row.isActive
            }));

            const invalidRow = payload.find(
                (row) => !row.sourceField || !row.targetField
            );
            if (invalidRow) {
                this.showToast(
                    'Missing fields',
                    `Source/Target empty. Source="${invalidRow.sourceField}", Target="${invalidRow.targetField}"`,
                    'error'
                );
                return;
            }

            const typeMismatch = payload.find((row) => {
                const sourceType = this.sourceTypeMap[row.sourceField];
                const targetType = this.targetTypeMap[row.targetField];
                return sourceType && targetType && sourceType !== targetType;
            });
            if (typeMismatch) {
                const sourceType = this.sourceTypeMap[typeMismatch.sourceField];
                const targetType = this.targetTypeMap[typeMismatch.targetField];
                this.showToast(
                    'Type mismatch',
                    `Source type "${sourceType}" does not match target type "${targetType}".`,
                    'error'
                );
                return;
            }

            this.mappingsOutputJson = JSON.stringify(payload);
            this.deletedIdsJson = JSON.stringify(this.deletedIds);
            this.hasSaved = true;
            this.showToast('Success', 'Mappings prepared for Flow save.', 'success');
        } catch (error) {
            this.showToast('Error', this.normalizeError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    syncOutputs() {
        const payload = this.mappings.map((row) => ({
            id: row.id,
            label: row.label,
            sourceField: row.sourceField,
            targetField: row.targetField,
            overwriteRule: row.overwriteRule,
            transform: row.transform,
            isActive: row.isActive
        }));
        this.mappingsOutputJson = JSON.stringify(payload);
        this.deletedIdsJson = JSON.stringify(this.deletedIds);
        this.persistDraftToSession();
    }

    @api
    validate() {
        this.mergeUiValues();
        this.syncOutputs();
        if (!this.hasSaved) {
            return {
                isValid: false,
                errorMessage: 'Please click Save before continuing.'
            };
        }
        return { isValid: true };
    }

    mapRecord(record) {
        const resolvedId = record?.id || record?.Id || null;
        return {
            key: resolvedId || `row-${Date.now()}`,
            id: resolvedId,
            label: record?.label || record?.Name || '',
            sourceField: record?.sourceField || record?.SourceField__c || '',
            targetField: record?.targetField || record?.TargetField__c || '',
            overwriteRule:
                record?.overwriteRule || record?.OverwriteRule__c || DEFAULT_OVERWRITE_RULE,
            transform:
                record?.transform || record?.Transform__c || DEFAULT_TRANSFORM,
            isActive:
                record?.isActive !== undefined
                    ? record.isActive
                    : record?.IsActive__c,
            isNew: false
        };
    }

    mergeUiValues() {
        const updates = {};
        const elements = this.template.querySelectorAll('[data-index][name]');
        elements.forEach((element) => {
            const index = Number(element.dataset.index);
            if (Number.isNaN(index)) {
                return;
            }
            const name = element.name;
            let value;
            if (element.type === 'toggle') {
                value = element.checked;
            } else {
                value = element.value;
            }
            if (!updates[index]) {
                updates[index] = {};
            }
            updates[index][name] = value;
        });

        const merged = this.mappings.map((row, index) =>
            updates[index] ? { ...row, ...updates[index] } : row
        );
        this.mappings = merged;
        return merged;
    }

    buildTypeMap(options) {
        const map = {};
        if (!options) {
            return map;
        }
        options.forEach((option) => {
            map[option.apiName] = option.dataType;
        });
        return map;
    }

    persistDraftToSession() {
        try {
            if (!this.useSessionDraft) {
                return;
            }
            if (!window?.sessionStorage) {
                return;
            }
            window.sessionStorage.setItem(
                'twinFieldMappingDraft',
                this.mappingsOutputJson || ''
            );
            window.sessionStorage.setItem(
                'twinFieldMappingDeleted',
                this.deletedIdsJson || ''
            );
        } catch (error) {
            // Ignore storage errors
        }
    }

    restoreDraftFromSession() {
        try {
            if (!this.useSessionDraft) {
                return;
            }
            if (!window?.sessionStorage) {
                return;
            }
            if (!this._mappingsJson) {
                const draft = window.sessionStorage.getItem('twinFieldMappingDraft');
                if (draft) {
                    this.mappingsJson = draft;
                }
            }
            const deleted = window.sessionStorage.getItem('twinFieldMappingDeleted');
            if (deleted) {
                this.deletedIdsJson = deleted;
                this.deletedIds = JSON.parse(deleted);
            }
        } catch (error) {
            // Ignore storage errors
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join('; ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}
