public with sharing class PatientTrackerController {
    // ======== Custom Metadata config (adjust names if needed) ========
    private static final String CMT_TYPE        = 'Patient_Tracker_Indicator__mdt';
    private static final String F_ORDER         = 'Order__c';
    private static final String F_OBJECT        = 'Object_Api_Name__c';
    private static final String F_PARENT_LOOKUP = 'Parent_Lookup_Field__c';
    private static final String F_STATUS_FIELD  = 'Object_Status_Field_Name__c';
    // =================================================================

    // ---------- DTOs ----------
    public class Config {
        @AuraEnabled public Integer order;
        @AuraEnabled public String  sobjectApiName;
        @AuraEnabled public String  parentLookupFieldApiName;
        @AuraEnabled public String  statusFieldApiName;
        @AuraEnabled public String  objectLabel;
    }
    public class Stage {
        @AuraEnabled public String label; // shown under the dot
        @AuraEnabled public String value; // e.g., "Referral: Working"
        public Stage(String l, String v){ label = l; value = v; }
    }
    public class Row {
        @AuraEnabled public Id      parentId;
        @AuraEnabled public String  parentName;
        @AuraEnabled public String  parentStatusValue;
        @AuraEnabled public Datetime parentCreated; // NEW: Referral (Order=1) CreatedDate

        @AuraEnabled public Id      childId;   // deepest child (if any)
        @AuraEnabled public String  childName;
        @AuraEnabled public String  childStatusValue;

        @AuraEnabled public String  currentStageValue;
        @AuraEnabled public Datetime lastModified;

        @AuraEnabled public Boolean isDirectToOrder;
        @AuraEnabled public String  childDisplayValue;
    }
    public class CaseDTO {
        @AuraEnabled public Id     id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isClosed;
        @AuraEnabled public String ownerName;
    }
    public class Response {
        @AuraEnabled public List<Stage> stages;
        @AuraEnabled public List<Row>   rows;
        @AuraEnabled public String parentObjectApiName;
        @AuraEnabled public String parentObjectLabel;
        @AuraEnabled public String childObjectApiName;
        @AuraEnabled public String childObjectLabel;
    }

    // ---------- Public: main data for LWC ----------
    @AuraEnabled(cacheable=true)
    public static Response getPatientTrackerData(Id recordId, String objectApiName){
        if (recordId == null) return new Response();

        // 1) Load ALL configured orders (1..N) from Custom Metadata
        List<SObject> md = Database.query(
            'SELECT ' + F_ORDER + ',' + F_OBJECT + ',' + F_PARENT_LOOKUP + ',' + F_STATUS_FIELD +
            ' FROM ' + CMT_TYPE + ' ORDER BY ' + F_ORDER
        );
        if (md.isEmpty()) throw new AuraHandledException('No custom metadata found for patient tracker.');

        Map<Integer, Config> byOrder = new Map<Integer, Config>();
        List<Integer> orders = new List<Integer>();
        
        for (SObject rec : md) {
            Config c = new Config();
            Object ov = rec.get(F_ORDER);
            Integer ord = (ov instanceof Integer) ? (Integer)ov
                        : (ov instanceof Decimal) ? ((Decimal)ov).intValue()
                        : Integer.valueOf(String.valueOf(ov));
            c.order = ord;
            c.sobjectApiName           = (String)rec.get(F_OBJECT);
            c.parentLookupFieldApiName = (String)rec.get(F_PARENT_LOOKUP);
            c.statusFieldApiName       = (String)rec.get(F_STATUS_FIELD);

            Schema.SObjectType sot = Schema.getGlobalDescribe().get(c.sobjectApiName);
            if (sot == null) throw new AuraHandledException('Unknown sObject: ' + c.sobjectApiName);
            Schema.DescribeSObjectResult d = sot.getDescribe();
            c.objectLabel = d.getLabel();

            Map<String, Schema.SObjectField> fmap = d.fields.getMap();
            if (!String.isBlank(c.parentLookupFieldApiName) && !fmap.containsKey(c.parentLookupFieldApiName))
                throw new AuraHandledException('Invalid parent field on ' + c.sobjectApiName + ': ' + c.parentLookupFieldApiName);
            if (!fmap.containsKey(c.statusFieldApiName))
                throw new AuraHandledException('Invalid status field on ' + c.sobjectApiName + ': ' + c.statusFieldApiName);

            byOrder.put(ord, c);
            orders.add(ord);
        }
        orders.sort();
        if (orders.isEmpty() || !byOrder.containsKey(1))
            throw new AuraHandledException('Expected at least Order=1 metadata.');

        Config c1 = byOrder.get(1);
        Config c2 = byOrder.containsKey(2) ? byOrder.get(2) : null;

        // 2) Build stage list across ALL configured orders
        List<Stage> allStages = new List<Stage>();
        for (Integer k : orders) allStages.addAll(describeStages(byOrder.get(k)));

        // 3) Build rows depending on hosting context
        List<Row> rows = new List<Row>();

        if (objectApiName == c1.sobjectApiName) {
            // On a level-1 record: that single record as parent
            SObject p = Database.query(
                'SELECT Id, Name, ' + c1.statusFieldApiName + ', LastModifiedDate, CreatedDate ' +
                'FROM ' + c1.sobjectApiName + ' WHERE Id = :recordId'
            );
            Row r = baseRowFromParent(p, c1);
            attachDeepestChild(r, byOrder, orders, new Set<Id>{ r.parentId }, 2); // walk down
            rows.add(r);

        } else if (objectApiName == 'Account') {
            // On Account: ONLY most recent level-1 (Account or PersonContact)
            Account a = [SELECT Id, PersonContactId FROM Account WHERE Id = :recordId LIMIT 1];
            Set<Id> anchors = new Set<Id>{ a.Id };
            if (a.PersonContactId != null) anchors.add(a.PersonContactId);

            List<SObject> parents = anchors.isEmpty() ? new List<SObject>() :
                Database.query(
                    'SELECT Id, Name, ' + c1.statusFieldApiName + ', ' + c1.parentLookupFieldApiName + ', LastModifiedDate, CreatedDate ' +
                    'FROM ' + c1.sobjectApiName +
                    ' WHERE ' + c1.parentLookupFieldApiName + ' IN :anchors ' +
                    ' ORDER BY CreatedDate DESC ' +
                    ' LIMIT 1'
                );
            if (!parents.isEmpty()) {
                Row r = baseRowFromParent(parents[0], c1);
                attachDeepestChild(r, byOrder, orders, new Set<Id>{ r.parentId }, 2);
                rows.add(r);
            }

        } else {
            // Is the host object one of the configured levels (≥ 2)?
            Boolean isConfiguredHost = false;
            Integer hostLevel = null;
            for (Integer k : orders) {
                if (byOrder.get(k).sobjectApiName == objectApiName) {
                    isConfiguredHost = true;
                    hostLevel = k;
                    break;
                }
            }

            if (isConfiguredHost && hostLevel != null && hostLevel > 1) {
                Config cHost = byOrder.get(hostLevel);

                // Load host record (include its parent lookup if level > 1)
                String hostSoql = 'SELECT Id, Name, ' + cHost.statusFieldApiName +
                                    (hostLevel > 1 && !String.isBlank(cHost.parentLookupFieldApiName) ? (', ' + cHost.parentLookupFieldApiName) : '') +
                                    ', LastModifiedDate, CreatedDate ' +
                                    'FROM ' + cHost.sobjectApiName + ' WHERE Id = :recordId';
                SObject host = Database.query(hostSoql);

                // Walk UP to level 1 (using metadata-defined parent lookups)
                SObject root = null;
                if (hostLevel == 1) {
                    root = host;
                } else {
                    SObject curr = host;
                    Integer currLevel = hostLevel;
                    while (currLevel > 1) {
                        Config curCfg = byOrder.get(currLevel);
                        String upField = curCfg.parentLookupFieldApiName;
                        if (String.isBlank(upField)) break; // malformed metadata
                        Id pid = (Id)curr.get(upField);
                        if (pid == null) break; // no parent → direct-to-order
                        Config parentCfg = byOrder.get(currLevel - 1);
                        String upSoql = 'SELECT Id, Name, ' + parentCfg.statusFieldApiName +
                                        (currLevel - 1 > 1 && !String.isBlank(parentCfg.parentLookupFieldApiName) ? (', ' + parentCfg.parentLookupFieldApiName) : '') +
                                        ', LastModifiedDate, CreatedDate ' +
                                        'FROM ' + parentCfg.sobjectApiName + ' WHERE Id = :pid';
                        curr = Database.query(upSoql);
                        currLevel = currLevel - 1;
                    }
                    root = curr; // either reached level 1 or stopped where parent was missing
                }

                // If we found a real Order=1 parent, build a normal row (NOT direct-to-order)
                if (root != null) {
                    String rootApi = root.getSObjectType().getDescribe().getName();
                    if (rootApi == c1.sobjectApiName) {
                        Row r = baseRowFromParent(root, c1);

                        // Prefer the furthest descendant after the host level, else the host itself
                        Set<Id> startIds = new Set<Id>{ (Id)host.get('Id') };
                        Row tmp = new Row(); tmp.parentId = (Id)host.get('Id');
                        attachDeepestChild(tmp, byOrder, orders, startIds, hostLevel + 1);

                        if (tmp.childId != null) {
                            r.childId           = tmp.childId;
                            r.childName         = tmp.childName;
                            r.childStatusValue  = tmp.childStatusValue;
                            r.currentStageValue = tmp.currentStageValue;
                        } else {
                            // No deeper child → show the host
                            r.childId           = (Id)host.get('Id');
                            r.childName         = (String)host.get('Name');
                            r.childStatusValue  = (String)host.get(cHost.statusFieldApiName);
                            r.currentStageValue = cHost.objectLabel + ': ' + r.childStatusValue;
                        }
                        rows.add(r);
                    } else {
                        // Unexpected: walked up but top wasn't the Order=1 object; treat as direct to order
                        Row r = new Row();
                        r.isDirectToOrder   = true;
                        r.childId           = (Id)host.get('Id');
                        r.childName         = (String)host.get('Name');
                        r.childStatusValue  = (String)host.get(cHost.statusFieldApiName);
                        r.currentStageValue = cHost.objectLabel + ': ' + r.childStatusValue;
                        r.lastModified      = (Datetime)host.get('LastModifiedDate');
                        rows.add(r);
                    }
                } else {
                    // No parent chain → truly Direct to Order
                    Row r = new Row();
                    r.isDirectToOrder   = true;
                    r.childId           = (Id)host.get('Id');
                    r.childName         = (String)host.get('Name');
                    r.childStatusValue  = (String)host.get(cHost.statusFieldApiName);
                    r.currentStageValue = cHost.objectLabel + ': ' + r.childStatusValue;
                    r.lastModified      = (Datetime)host.get('LastModifiedDate');
                    rows.add(r);
                }

            } else {
                // Other host (e.g., Contact or custom referenced by Order=1 parent lookup): normal filter by that record
                List<SObject> parents = Database.query(
                    'SELECT Id, Name, ' + c1.statusFieldApiName + ', ' + c1.parentLookupFieldApiName + ', LastModifiedDate, CreatedDate ' +
                    'FROM ' + c1.sobjectApiName +
                    ' WHERE ' + c1.parentLookupFieldApiName + ' = :recordId ' +
                    ' ORDER BY CreatedDate DESC'
                );
                for (SObject p : parents) {
                    Row r = baseRowFromParent(p, c1);
                    attachDeepestChild(r, byOrder, orders, new Set<Id>{ r.parentId }, 2);
                    rows.add(r);
                }
            }
        }

        // 4) Build response
        Response resp = new Response();
        resp.stages = allStages;
        resp.rows   = rows;
        resp.parentObjectApiName = c1.sobjectApiName;
        resp.parentObjectLabel   = c1.objectLabel;
        if (c2 != null) {
            resp.childObjectApiName = c2.sobjectApiName;
            resp.childObjectLabel   = c2.objectLabel;
        }
        return resp;
    }

    // Build a base Row from an Order=1 parent record
    private static Row baseRowFromParent(SObject p, Config c1){
        Row r = new Row();
        r.parentId          = (Id)p.get('Id');
        r.parentName        = (String)p.get('Name');
        r.parentCreated     = (Datetime)p.get('CreatedDate'); // Added 9/15/2025 to set color based on Order = 1 createdDate
        r.parentStatusValue = (String)p.get(c1.statusFieldApiName);
        r.lastModified      = (Datetime)p.get('LastModifiedDate');
        r.isDirectToOrder   = false;
        if (r.parentStatusValue != null) r.currentStageValue = c1.objectLabel + ': ' + r.parentStatusValue;
        return r;
    }

    // From a set of parent ids at a given starting level, walk DOWN to find the newest child per branch, through level N, and attach to row.
    private static void attachDeepestChild(Row r, Map<Integer, Config> byOrder, List<Integer> orders, Set<Id> startParentIds, Integer startLevel){
        if (startParentIds == null || startParentIds.isEmpty()) return;

        Map<Id, SObject> deepestChildByRoot = new Map<Id, SObject>();
        Map<Id, Config>  deepestCfgByRoot   = new Map<Id, Config>();
        Map<Id, String>  deepestStatusByRoot= new Map<Id, String>();

        Set<Id> currentParentIds = new Set<Id>(startParentIds);
        Map<Id, Id> parentToRoot = new Map<Id, Id>();
        for (Id pid : currentParentIds) parentToRoot.put(pid, pid);

        for (Integer lvl : orders) {
            if (lvl < startLevel) continue;
            Config cc = byOrder.get(lvl);
            if (cc == null || currentParentIds.isEmpty()) break;

            List<SObject> kids = Database.query(
                'SELECT Id, Name, ' + cc.statusFieldApiName + ', ' + cc.parentLookupFieldApiName + ', LastModifiedDate, CreatedDate ' +
                'FROM ' + cc.sobjectApiName +
                ' WHERE ' + cc.parentLookupFieldApiName + ' IN :currentParentIds'
            );

            Map<Id, SObject> newestByParent = new Map<Id, SObject>();
            for (SObject ch : kids) {
                Id pid = (Id)ch.get(cc.parentLookupFieldApiName);
                if (pid == null) continue;
                SObject prev = newestByParent.get(pid);
                if (prev == null || ((Datetime)ch.get('CreatedDate')) > ((Datetime)prev.get('CreatedDate'))) {
                    newestByParent.put(pid, ch);
                }
            }

            Set<Id> nextParentIds = new Set<Id>();
            Map<Id, Id> nextParentToRoot = new Map<Id, Id>();
            for (Id parentId : newestByParent.keySet()) {
                SObject ch = newestByParent.get(parentId);
                Id root = parentToRoot.get(parentId);
                if (root == null) continue;

                deepestChildByRoot.put(root, ch);
                deepestCfgByRoot.put(root, cc);
                deepestStatusByRoot.put(root, (String)ch.get(cc.statusFieldApiName));

                Id chId = (Id)ch.get('Id');
                nextParentIds.add(chId);
                nextParentToRoot.put(chId, root);
            }
            currentParentIds = nextParentIds;
            parentToRoot     = nextParentToRoot;
        }

        Id rootId = startParentIds.iterator().hasNext() ? startParentIds.iterator().next() : null;
        if (rootId != null && deepestChildByRoot.containsKey(rootId)) {
            SObject ch = deepestChildByRoot.get(rootId);
            Config  cc = deepestCfgByRoot.get(rootId);
            r.childId          = (Id)ch.get('Id');
            r.childName        = (String)ch.get('Name');
            r.childStatusValue = deepestStatusByRoot.get(rootId);
            if (cc != null && r.childStatusValue != null) {
                r.currentStageValue = cc.objectLabel + ': ' + r.childStatusValue;
            }
        }
    }

    // ---------- Bulk Cases for initial load ----------
    @AuraEnabled(cacheable=true)
    public static Map<Id, List<CaseDTO>> getCasesForRows(List<Id> parentIds, List<Id> childIds) {
        Map<Id, List<CaseDTO>> result = new Map<Id, List<CaseDTO>>();
        if ((parentIds == null || parentIds.isEmpty()) && (childIds == null || childIds.isEmpty())) {
            return result;
        }

        Integer maxLen = Math.max(parentIds == null ? 0 : parentIds.size(),
                                    childIds  == null ? 0 : childIds.size());

        Map<Id, String> targetTypeById = new Map<Id, String>();
        Map<String, Set<Id>> idsByType = new Map<String, Set<Id>>();

        for (Integer i = 0; i < maxLen; i++) {
            Id pid = (parentIds != null && i < parentIds.size()) ? parentIds[i] : null;
            Id cid = (childIds  != null && i < childIds.size())  ? childIds[i]  : null;
            Id tid = (cid != null) ? cid : pid;
            if (tid == null) continue;

            Schema.SObjectType st = tid.getSObjectType();
            if (st == null) continue;
            String api = st.getDescribe().getName();

            targetTypeById.put(tid, api);
            if (!idsByType.containsKey(api)) idsByType.put(api, new Set<Id>());
            idsByType.get(api).add(tid);
        }

        if (idsByType.isEmpty()) return result;

        for (String typeApi : idsByType.keySet()) {
            String lookupField = findCaseLookupField(typeApi);
            if (String.isBlank(lookupField)) continue;

            Set<Id> targets = idsByType.get(typeApi);
            String soql =
                'SELECT Id, CaseNumber, Subject, Type, Status, IsClosed, Owner.Name, ' + lookupField +
                ' FROM Case ' +
                ' WHERE ' + lookupField + ' IN :targets ' +
                ' ORDER BY IsClosed ASC, CreatedDate DESC';

            for (Case c : Database.query(soql)) {
                Id key = (Id)c.get(lookupField);
                if (key == null) continue;

                if (!result.containsKey(key)) result.put(key, new List<CaseDTO>());
                CaseDTO dto = new CaseDTO();
                dto.id         = c.Id;
                dto.caseNumber = c.CaseNumber;
                dto.subject    = c.Subject;
                dto.type       = c.Type;
                dto.status     = c.Status;
                dto.isClosed   = c.IsClosed;
                dto.ownerName  = (c.Owner != null ? c.Owner.Name : null);
                result.get(key).add(dto);
            }
        }
        return result;
    }

    // Find which Case lookup points to a target object (dynamic; no hard-coding)
    private static String findCaseLookupField(String targetObjectApiName) {
        Schema.DescribeSObjectResult dCase = Schema.getGlobalDescribe().get('Case').getDescribe();
        Map<String, Schema.SObjectField> fmap = dCase.fields.getMap();
        for (String fn : fmap.keySet()) {
            Schema.DescribeFieldResult fd = fmap.get(fn).getDescribe();
            if (fd.getType() == Schema.DisplayType.Reference) {
                for (Schema.SObjectType rt : fd.getReferenceTo()) {
                    if (rt.getDescribe().getName() == targetObjectApiName) {
                        return fn; // first match wins
                    }
                }
            }
        }
        return null;
    }

    private static List<Stage> describeStages(Config c) {
        List<Stage> out = new List<Stage>();
        Schema.SObjectType st = Schema.getGlobalDescribe().get(c.sobjectApiName);
        if (st == null) return out;
        Schema.DescribeSObjectResult d = st.getDescribe();
        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        Schema.SObjectField fld = fmap.get(c.statusFieldApiName);
        if (fld == null) return out;
        Schema.DescribeFieldResult fd = fld.getDescribe();

        String prefix = d.getLabel() + ': ';
        if (fd.getType() == Schema.DisplayType.Picklist || fd.getType() == Schema.DisplayType.MultiPicklist) {
            for (Schema.PicklistEntry pe : fd.getPicklistValues()) {
                out.add(new Stage(pe.getLabel(), prefix + pe.getValue()));
            }
        } else {
            out.add(new Stage('Started',     prefix + 'Started'));
            out.add(new Stage('In Progress', prefix + 'In Progress'));
            out.add(new Stage('Complete',    prefix + 'Complete'));
        }
        return out;
    }
}
