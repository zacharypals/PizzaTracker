import { LightningElement, api, wire, track } from 'lwc';
import getPatientTrackerData from '@salesforce/apex/PatientTrackerController.getPatientTrackerData';
import getCasesForRows from '@salesforce/apex/PatientTrackerController.getCasesForRows';
import FORM_FACTOR from '@salesforce/client/formFactor';

export default class PatientTracker extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track rows = [];
    stages = [];
    parentApiName;
    parentLabel;
    childApiName;
    childLabel;
    isLoading = true;

    // Mobile detection
    isMobile = FORM_FACTOR === 'Small';

    @wire(getPatientTrackerData, { recordId: '$recordId', objectApiName: '$objectApiName' })
    async wiredData({ error, data }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading tracker data', error);
            this.rows = [];
            this.stages = [];
            this.isLoading = false;
            return;
        }
        if (!data) return;

        // Build rows immediately
        this.stages = data.stages || [];
        this.parentApiName = data.parentObjectApiName;
        this.parentLabel   = data.parentObjectLabel;
        this.childApiName  = data.childObjectApiName;
        this.childLabel    = data.childObjectLabel;

        this.rows = (data.rows || []).map(function(r) {
            const hasChild = !!r.childId;
            const headerPrefix = hasChild ? this.childLabel : this.parentLabel;
            const headerName   = hasChild
                ? (r.childDisplayValue || r.childName || '(unnamed)')
                : (r.parentName || '(unnamed)');
            const headerUrl    = hasChild
                ? (r.childId  ? '/lightning/r/' + this.childApiName  + '/' + r.childId  + '/view' : null)
                : (r.parentId ? '/lightning/r/' + this.parentApiName + '/' + r.parentId + '/view' : null);

            const keyId = r.parentId || r.childId;
            const contentId = 'section-content-' + keyId;

            // Compute age (days) from Referral (Order=1) CreatedDate, if present
            let ageDays = 0;
            if (r.parentCreated) {
                try {
                    const createdMs = new Date(r.parentCreated).getTime();
                    if (!isNaN(createdMs)) {
                        ageDays = Math.floor((Date.now() - createdMs) / 86400000);
                    }
                } catch(e) { /* ignore parse issues */ }
            }

            // Age-based base scheme: green (0–30), orange (31–60), red (61+)
            // Direct-to-order rows stay green by default.
            let baseScheme = 'green';
            if (!r.isDirectToOrder) {
                if (ageDays >= 61) baseScheme = 'red';
                else if (ageDays >= 31) baseScheme = 'orange';
            }

            return this.decorateRow({
                ...r,
                keyId,
                headerPrefix,
                headerName,
                headerUrl,

                // case state
                relatedCases: [],
                caseCount: 0,
                hasCases: false,
                casesLoaded: false,
                isFetchingCases: false,

                parentUrl: r.parentId ? '/lightning/r/' + this.parentApiName + '/' + r.parentId + '/view' : null,
                lastModifiedDisplay: r.lastModified
                    ? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(r.lastModified))
                    : '',

                // progress rendering state
                trackStyle: '',
                trackSegments: [],
                decoratedStages: [],
                labelRowStyle: '',

                // base scheme (can be overridden to 'blue' if fully complete)
                agingScheme: baseScheme,

                // accordion defaults (may auto-open if open cases)
                isOpen: false,
                contentId,
                sectionClass: 'slds-accordion__section',
                ariaHidden: 'true'
            });
        }, this);

        // Preload cases BEFORE clearing spinner (also sets default accordion open/closed)
        await this.preloadCasesForAllRows();

        this.isLoading = false;
        setTimeout(() => { this.updateTrackSpans(); }, 0);
    }

    // Prevent accordion toggle when clicking the header link
    onTitleClick(event) { event.stopPropagation(); }

    // ===== Color helpers =====
    // Per-scheme color along the track (t in [0,1])
    colorAtScheme(t, scheme) {
        if (t < 0) t = 0;
        if (t > 1) t = 1;

        if (scheme === 'orange') {
            const hue = 32;  // orange
            const sat = 80;
            const light = Math.round(74 - 26 * t); // 74% -> 48%
            return `hsl(${hue},${sat}%,${light}%)`;
        }
        if (scheme === 'red') {
            const hue = 0;   // red
            const sat = 75;
            const light = Math.round(74 - 26 * t);
            return `hsl(${hue},${sat}%,${light}%)`;
        }
        if (scheme === 'blue') {
            const hue = 210; // blue
            const sat = 80;
            const light = Math.round(74 - 26 * t);
            return `hsl(${hue},${sat}%,${light}%)`;
        }
        // default green
        const hue = 140, sat = Math.round(55 + 35 * t), light = Math.round(72 - 28 * t);
        return `hsl(${hue},${sat}%,${light}%)`;
    }
    schemeTrackColor(scheme) {
        if (scheme === 'orange') return '#F5A142';
        if (scheme === 'red')    return '#BA0517';
        if (scheme === 'blue')   return '#1B96FF';
        return '#52E081'; // green
    }

    mergeFinalReferralStage(baseStages) {
        const prefix = this.parentLabel ? (this.parentLabel + ': ') : '';
        let completeIdx = -1, cancelIdx = -1;
        let completeValue = '', cancelValue = '';
        for (let i = 0; i < baseStages.length; i++) {
            const v = baseStages[i].value || '';
            if (prefix && v.indexOf(prefix) !== 0) continue;
            const tail = v.substring(prefix.length).toLowerCase();
            if (tail === 'complete')  { completeIdx = i; completeValue = baseStages[i].value; }
            if (tail === 'canceled' || tail === 'cancelled') { cancelIdx = i; cancelValue = baseStages[i].value; }
        }
        if (completeIdx === -1 && cancelIdx === -1) {
            return { stages: baseStages.slice(), mergedIndex: -1, mergedValMap: {} };
        }
        const keep = [];
        for (let j = 0; j < baseStages.length; j++) {
            if (j === completeIdx || j === cancelIdx) continue;
            keep.push(baseStages[j]);
        }
        const maxIdx = Math.max(completeIdx, cancelIdx);
        const onlyOne = (completeIdx === -1) !== (cancelIdx === -1);
        let insertAt = onlyOne ? (completeIdx !== -1 ? completeIdx : cancelIdx) : (maxIdx - 1);
        if (insertAt < 0) insertAt = 0;
        if (insertAt > keep.length) insertAt = keep.length;
        const mergedValue = prefix + '__Final__Merged__';
        const mergedStages = keep.slice(0, insertAt).concat([{ label: 'Referral Complete', value: mergedValue }]).concat(keep.slice(insertAt));
        const map = {};
        if (completeValue) map[completeValue] = insertAt;
        if (cancelValue)  map[cancelValue]  = insertAt;
        return { stages: mergedStages, mergedIndex: insertAt, mergedValMap: map };
    }

    decorateRow(r) {
        const prefixRef = this.parentLabel ? (this.parentLabel + ': ') : '';
        const baseStages = this.stages;
        const mergeInfo = this.mergeFinalReferralStage(baseStages);
        let stagesForRow = mergeInfo.stages;
        const mergedIndex  = mergeInfo.mergedIndex;
        const mergedValMap = mergeInfo.mergedValMap || {};
        if (r.isDirectToOrder && mergedIndex >= 0) {
            stagesForRow = stagesForRow.slice();
            stagesForRow[mergedIndex] = { label: 'No Referral/Direct To Order', value: prefixRef + '__Direct__To__Order__' };
        }
        let currentIndex = -1;
        for (let i = 0; i < stagesForRow.length; i++) {
            if (stagesForRow[i].value === r.currentStageValue) { currentIndex = i; break; }
        }
        if (currentIndex === -1 && mergedIndex >= 0 && mergedValMap[r.currentStageValue] !== undefined) {
            currentIndex = mergedValMap[r.currentStageValue];
        }

        const FUTURE_GRAY = '#d8dde6', SUCCESS_GREEN = '#2e844a', ERROR_RED = '#ba0517';
        const DARK_ORANGE = '#C97300';
        const DARK_BLUE   = '#0B5CAB';
        const parentStatusLc = (r.parentStatusValue || '').toLowerCase();
        const isCanceled = parentStatusLc.indexOf('cancel') !== -1;

        // NEW: if fully complete (current is last index) and not canceled → override scheme to blue
        const count = stagesForRow.length;
        const isFullyComplete = (currentIndex >= 0 && currentIndex === count - 1 && !isCanceled);
        let scheme = isFullyComplete ? 'blue' : (r.agingScheme || 'green');

        const arr = [];
        for (let j = 0; j < count; j++) {
            const t = (count === 1) ? 0 : (j / (count - 1));
            let reached = (currentIndex >= 0) ? (j <= currentIndex) : false;
            if (r.isDirectToOrder && j < mergedIndex) {
                const val = stagesForRow[j].value || '';
                if (val && val.indexOf(prefixRef) === 0) reached = false;
            }
            let cls = 'slds-progress__item';
            if (currentIndex >= 0) {
                if (j < currentIndex) cls += ' slds-is-completed';
                else if (j === currentIndex) cls += ' slds-is-active';
            }
            let label = stagesForRow[j].label;
            let color;

            if (j === mergedIndex) {
                if (r.isDirectToOrder) {
                    color = reached ? this.colorAtScheme(t, scheme) : FUTURE_GRAY;
                } else {
                    // Final Referral stage (Complete or Canceled)
                    if (!reached) {
                        color = FUTURE_GRAY;
                    } else if (isCanceled) {
                        color = ERROR_RED; // canceled always red
                    } else {
                        // Referral Complete → slightly darker by scheme
                        if (scheme === 'orange') color = DARK_ORANGE;
                        else if (scheme === 'red') color = ERROR_RED;
                        else if (scheme === 'blue') color = DARK_BLUE;
                        else color = SUCCESS_GREEN;
                    }
                    label = isCanceled ? 'Referral Canceled' : 'Referral Complete';
                }
            } else {
                color = reached ? this.colorAtScheme(t, scheme) : FUTURE_GRAY;
            }

            // If fully complete, make the very last dot a darker blue
            if (isFullyComplete && j === count - 1 && reached && !isCanceled) {
                color = DARK_BLUE;
            }

            // Hide checkmark on canceled dot
            if (j === mergedIndex && !r.isDirectToOrder && isCanceled && reached) {
                cls += ' pt-no-check';
            }

            const style = 'background:' + color + ';border-color:' + color + ';' + (reached ? '' : 'opacity:.5;');
            arr.push({ label: label, value: stagesForRow[j].value, itemClass: cls, markerStyle: style });
        }
        r.decoratedStages = arr;

        // single current-stage label for mobile view
        r.currentStageLabel = (currentIndex >= 0 && arr[currentIndex]) ? arr[currentIndex].label : '';

        // compute label row style as before
        let n = arr.length; if (n < 1) n = 1;
        const halfPct = 50 / n;
        const full = 90 / n;
        r.labelRowStyle =
            'display:grid;grid-template-columns:repeat(' + n + ',1fr);gap:0;margin-top:.25rem;' +
            'padding-left:' + full + '%;padding-right:' + halfPct + '%;';

        // NEW: choose segment color based on (possibly overridden) scheme
        r.progressTrackColor = this.schemeTrackColor(scheme);

        return r;
    }

    // ===== Cases: preload and default-open if any open =====
    async preloadCasesForAllRows() {
        if (!this.rows || !this.rows.length) return;

        const parentIds = this.rows.map(r => r.parentId || null);
        const childIds  = this.rows.map(r => r.childId  || null);

        try {
            const mapResult = await getCasesForRows({ parentIds, childIds });

            const rowsNext = this.rows.map((row) => {
                const key = row.childId || row.parentId;
                const list = (mapResult && key && mapResult[key]) ? mapResult[key] : [];

                const cases = (list || []).map((ci) => {
                    const sLc = (ci.status || '').toLowerCase();
                    let cls = 'slds-badge pt-badge';
                    if (sLc.indexOf('closed') !== -1 || sLc.indexOf('resolved') !== -1) {
                        // neutral
                    } else if (sLc.indexOf('escalat') !== -1 || sLc.indexOf('urgent') !== -1) {
                        cls += ' pt-badge--error';
                    } else if (sLc.indexOf('open') !== -1 || sLc.indexOf('new') !== -1 || sLc.indexOf('work') !== -1 || sLc.indexOf('progress') !== -1) {
                        cls += ' pt-badge--warn';
                    }
                    return {
                        ...ci,
                        recordUrl: '/lightning/r/Case/' + ci.id + '/view',
                        statusClass: cls
                    };
                });

                const caseCount = cases.length;
                const hasOpen = cases.some(c => c.isClosed === false);

                const isOpen = hasOpen;
                const sectionClass = 'slds-accordion__section' + (isOpen ? ' slds-is-open' : '');
                const ariaHidden = isOpen ? 'false' : 'true';

                return {
                    ...row,
                    relatedCases: cases,
                    caseCount,
                    hasCases: caseCount > 0,
                    casesLoaded: true,
                    isFetchingCases: false,
                    isOpen,
                    sectionClass,
                    ariaHidden
                };
            });

            this.rows = rowsNext;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('getCasesForRows error', e);
            this.rows = this.rows.map(r => ({ ...r, casesLoaded: true, isFetchingCases: false }));
        }
    }

    renderedCallback() { this.updateTrackSpans(); }

    onToggle(evt) {
        const id = evt.currentTarget.getAttribute('data-row-id') || evt.target.getAttribute('data-row-id');
        if (!id) return;

        this.rows = this.rows.map((row) => {
            if (row.keyId === id) {
                const isOpen = !row.isOpen;
                const sc = 'slds-accordion__section' + (isOpen ? ' slds-is-open' : '');
                const ah = isOpen ? 'false' : 'true';
                return { ...row, isOpen: isOpen, sectionClass: sc, ariaHidden: ah };
            }
            return row;
        });

        setTimeout(() => { this.updateTrackSpans(); }, 0);
    }

    // Draw the gray baseline + colored segments between reached dots.
    updateTrackSpans() {
        const containers = this.template.querySelectorAll('.pt-progress');
        if (!containers || !containers.length) return;

        let needsUpdate = false;
        const newRows = this.rows.map((row) => row);

        for (let k = 0; k < containers.length; k++) {
            const el = containers[k];
            const rowId = el.getAttribute('data-row-id');
            if (!rowId) continue;

            const markers = el.querySelectorAll('.slds-progress__marker');
            if (!markers || !markers.length) continue;

            const containerRect = el.getBoundingClientRect();
            const firstRect = markers[0].getBoundingClientRect();
            const lastRect  = markers[markers.length - 1].getBoundingClientRect();

            const firstCenter = firstRect.left + (firstRect.width / 2);
            const lastCenter  = lastRect.left + (lastRect.width / 2);
            const leftPx  = Math.max(0, Math.round(firstCenter - containerRect.left));
            const rightPx = Math.max(0, Math.round(containerRect.right - lastCenter));
            const baseStyle = 'position:absolute;left:' + leftPx + 'px;right:' + rightPx + 'px;top:50%;height:2px;' +
                              'background:#e5e5e5;transform:translateY(-50%);border-radius:2px;';

            const items = el.querySelectorAll('.slds-progress__item');
            const segs = [];
            const rowRef = this.rows.find(r => r.keyId === rowId);
            const segColor = (rowRef && rowRef.progressTrackColor) ? rowRef.progressTrackColor : '#52E081';

            for (let i = 0; i < items.length - 1; i++) {
                const nextReached = items[i + 1].classList.contains('slds-is-completed') ||
                                    items[i + 1].classList.contains('slds-is-active');
                if (!nextReached) continue;

                const startRect = markers[i].getBoundingClientRect();
                const endRect   = markers[i + 1].getBoundingClientRect();
                const startCenter = startRect.left + (startRect.width / 2);
                const endCenter   = endRect.left + (endRect.width / 2);

                const leftPxC  = Math.max(0, Math.round(startCenter - containerRect.left));
                const rightPxC = Math.max(0, Math.round(containerRect.right - endCenter));
                const style = 'position:absolute;left:' + leftPxC + 'px;right:' + rightPxC + 'px;top:50%;height:2px;' +
                              'background:' + segColor + ';transform:translateY(-50%);border-radius:2px;';
                segs.push({ key: rowId + '-' + i, style: style });
            }

            for (let r = 0; r < newRows.length; r++) {
                if (newRows[r].keyId === rowId &&
                    (newRows[r].trackStyle !== baseStyle || JSON.stringify(newRows[r].trackSegments) !== JSON.stringify(segs))) {
                    newRows[r] = { ...newRows[r], trackStyle: baseStyle, trackSegments: segs };
                    needsUpdate = true;
                    break;
                }
            }
        }
        if (needsUpdate) this.rows = newRows;
    }

    get hasRows() { return this.rows && this.rows.length > 0; }
}
