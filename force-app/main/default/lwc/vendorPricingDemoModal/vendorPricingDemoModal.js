import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { createSampleQuotes, validateDemoLine } from './vendorPricingDemoData';

/**
 * Presentation-only modal. Never calls Apex, changes parent row state or saves prices.
 * The future production integration will replace createSampleQuotes with Apex results.
 */
export default class VendorPricingDemoModal extends LightningModal {
    @api selectedLines = [];

    selectedRowKey = '';
    quotes = [];
    selectedQuoteId = '';
    manualOverride = null;
    hasGenerated = false;

    connectedCallback() {
        this.selectedRowKey = this.selectedLines?.[0]?.rowKey || '';
    }

    get lineOptions() {
        return (this.selectedLines || []).map((line, index) => ({
            label: `Job ${line.jobNumber || '—'} · ${line.partNumber || line.lossComponentName || `Part ${index + 1}`}${line.isUnsaved ? ' · Unsaved' : ''}`,
            value: line.rowKey
        }));
    }

    get hasMultipleLines() {
        return this.lineOptions.length > 1;
    }

    get currentLine() {
        return (this.selectedLines || []).find((line) => line.rowKey === this.selectedRowKey)
            || this.selectedLines?.[0] || null;
    }

    get displayPartNumber() {
        return this.currentLine?.partNumber || 'Not entered';
    }

    get displayComponent() {
        return this.currentLine?.lossComponentName || 'Not selected';
    }

    get displayQuantity() {
        return this.currentLine?.adjustedQuantity ?? '—';
    }

    get displayJob() {
        return this.currentLine?.jobNumber || '—';
    }

    get searchBasis() {
        return String(this.currentLine?.partNumber || '').trim()
            ? 'Part Number' : 'Loss Component';
    }

    get validationMessages() {
        return validateDemoLine(this.currentLine);
    }

    get isGenerateDisabled() {
        return this.validationMessages.length > 0;
    }

    get hasQuotes() {
        return this.quotes.length > 0;
    }

    get quotesForDisplay() {
        const lowest = this.quotes[0]?.comparisonAmount;
        return this.quotes.map((quote) => ({
            ...quote,
            isLowest: quote.comparisonAmount === lowest,
            isSelected: quote.id === this.selectedQuoteId,
            cardClass: `demo-quote-card${quote.id === this.selectedQuoteId ? ' is-selected' : ''}${quote.comparisonAmount === lowest ? ' is-lowest' : ''}`,
            selectLabel: quote.id === this.selectedQuoteId ? 'Selected for Preview' : 'Select Quote for Preview',
            selectVariant: quote.id === this.selectedQuoteId ? 'brand' : 'neutral'
        }));
    }

    get currentSelection() {
        return this.quotes.find((q) => q.id === this.selectedQuoteId) || null;
    }

    get hasSelection() {
        return Boolean(this.currentSelection);
    }

    get selectedVendor() {
        return this.currentSelection?.vendorName || '';
    }

    get selectedCatalog() {
        return this.currentSelection?.catalog || '';
    }

    get chosenVendorTotal() {
        return this.currentSelection?.vendorTotalPrice;
    }

    get previewAdjustedRate() {
        if (!this.hasSelection) return null;
        if (this.manualOverride !== null && this.manualOverride !== '') {
            const value = Number(this.manualOverride);
            if (Number.isFinite(value) && value >= 0) return value;
        }
        return this.chosenVendorTotal;
    }

    get hasValidOverride() {
        return this.manualOverride === null || this.manualOverride === '' ||
            (Number.isFinite(Number(this.manualOverride)) && Number(this.manualOverride) >= 0);
    }

    get hasOverride() {
        return this.hasSelection && this.manualOverride !== null && this.manualOverride !== '';
    }

    handleLineChange(event) {
        this.selectedRowKey = event.detail.value;
        this.resetQuotes();
    }

    handleGenerate() {
        if (this.isGenerateDisabled) return;
        this.quotes = createSampleQuotes(this.currentLine);
        this.selectedQuoteId = '';
        this.manualOverride = null;
        this.hasGenerated = true;
    }

    handleSelectQuote(event) {
        this.selectedQuoteId = event.currentTarget.dataset.quoteId;
        this.manualOverride = null;
    }

    handleOverrideChange(event) {
        this.manualOverride = event.detail.value;
    }

    handleResetOverride() {
        this.manualOverride = null;
    }

    handleReset() {
        this.resetQuotes();
    }

    resetQuotes() {
        this.quotes = [];
        this.selectedQuoteId = '';
        this.manualOverride = null;
        this.hasGenerated = false;
    }

    handleClose() {
        this.close();
    }
}