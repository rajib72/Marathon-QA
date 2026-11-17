/**
 * ONLY illustrative UI preview data. These are NOT Teal/C&K quotations.
 * Production: remove this provider and use normalized quotes returned by Apex.
 */
export const DEMO_ONLY = true;

export function validateDemoLine(line) {
    const errors = [];
    if (!line || line.detailType !== 'Part') {
        errors.push('Pricing comparison is available for Part lines in this preview.');
        return errors;
    }
    const quantity = Number(line.adjustedQuantity);
    if (!Number.isFinite(quantity) || quantity <= 0) {
        errors.push('Enter a positive Adjusted Quantity.');
    }
    if (!String(line.partNumber || '').trim() &&
        !String(line.lossComponentName || '').trim()) {
        errors.push('Enter a Part Number or select a Loss Component.');
    }
    return errors;
}

export function createSampleQuotes(line) {
    if (validateDemoLine(line).length) return [];
    const quantity = Number(line.adjustedQuantity);
    // Prices, shipping, warranty and availability below are invented for UI illustration.
    const examples = [
        { id: 'DEMO_TEAL_OEM', vendorCode: 'TEAL', vendorName: 'Teal Parts', catalog: 'New OEM',
          unitPrice: 205, shipping: 18, warranty: 'Illustrative 12 months',
          availability: 'Sample: Available', delivery: 'Sample: 3–5 business days' },
        { id: 'DEMO_TEAL_AFTERMARKET', vendorCode: 'TEAL', vendorName: 'Teal Parts',
          catalog: 'New Aftermarket', unitPrice: 179, shipping: 24,
          warranty: 'Illustrative 12 months', availability: 'Sample: Available',
          delivery: 'Sample: 2–4 business days' },
        { id: 'DEMO_CK_OEM', vendorCode: 'CK', vendorName: 'C&K', catalog: 'New OEM',
          unitPrice: 198, shipping: 15, warranty: 'Illustrative 24 months',
          availability: 'Sample: Limited', delivery: 'Sample: 4–6 business days' },
        { id: 'DEMO_CK_REMAN', vendorCode: 'CK', vendorName: 'C&K',
          catalog: 'Remanufactured', unitPrice: 165, shipping: 29,
          warranty: 'Illustrative 12 months', availability: 'Sample: Available',
          delivery: 'Sample: 3–6 business days' }
    ];
    return examples.map((example) => {
        const comparisonAmount = Number((example.unitPrice * quantity).toFixed(2));
        return {
            ...example,
            quantity,
            comparisonAmount,
            // Sample vendor-returned Total Price; do NOT recompute in the actual integration.
            vendorTotalPrice: Number((comparisonAmount + example.shipping).toFixed(2)),
            reference: example.id.replace('DEMO_', 'SAMPLE-')
        };
    }).sort((a, b) => a.comparisonAmount - b.comparisonAmount);
}