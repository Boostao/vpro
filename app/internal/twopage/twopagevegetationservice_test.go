package twopage

import (
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"testing"
)

func vegetationFacade(t *testing.T, contexts *vprocore.ContextService) *TwoPageVegetationService {
	t.Helper()
	service, err := NewTwoPageVegetationService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	return service
}

func vegetationAttemptJSON(t *testing.T, request twoPageVegetationRequest) string {
	t.Helper()
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

func TestTwoPageVegetationServiceCommitAndReadonlyRecovery(t *testing.T) {
	for _, form := range []string{"SubVegAXL_BC", "SubVegAXL", "SubVegCXL", "SubVegDXL"} {
		t.Run(form, func(t *testing.T) {
			contexts, state, db, request := vegetationWriteFixture(t, false, form, 3)
			raw := vegetationAttemptJSON(t, request)
			before := vprotest.DatabaseBytes(t, contexts.Projects.Sqlite.Attachments)
			readonly := vegetationFacade(t, contexts)
			if result, err := readonly.GetOriginal(context.Background(), state.ContextID, "108050", form); result == nil || err != nil {
				t.Fatal("physical original refused", result, err)
			}
			if result, err := readonly.GetSpeciesReferences(context.Background(), state.ContextID, "108050", form); result == nil || err != nil {
				t.Fatal("physical Species definitions refused", result, err)
			}
			if result, err := readonly.RecoverReceipt(context.Background(), state.ContextID, raw); result != nil || err != nil {
				t.Fatal("missing history is not unresolved nil", result, err)
			}
			if !reflect.DeepEqual(before, vprotest.DatabaseBytes(t, contexts.Projects.Sqlite.Attachments)) {
				t.Fatal("readonly reads created source/schema/history")
			}
			enabled := vegetationFacade(t, contexts)
			priorAudits := soilWriteCount(t, db, "Sample_Audit")
			result, err := enabled.Save(context.Background(), state.ContextID, raw)
			if err != nil || result == nil || !result.DidCommit || result.Replayed ||
				soilWriteCount(t, db, "Sample_Audit") != priorAudits+2 || soilWriteCount(t, db, twoPageVegetationHistoryTable) != 1 {
				t.Fatal("facade did not retain exact atomic writer result", result, err)
			}
			before = vprotest.DatabaseBytes(t, contexts.Projects.Sqlite.Attachments)
			recovered, err := readonly.RecoverReceipt(context.Background(), state.ContextID, raw)
			if err != nil || recovered == nil || recovered.DidCommit || !recovered.Replayed ||
				!reflect.DeepEqual(recovered.History, result.History) ||
				!reflect.DeepEqual(before, vprotest.DatabaseBytes(t, contexts.Projects.Sqlite.Attachments)) {
				t.Fatal("readonly recovery lost provenance or wrote data", recovered, err)
			}
		})
	}
}

func TestTwoPageVegetationServiceStrictTransportAndExplicitErrors(t *testing.T) {
	contexts, state, _, request := vegetationWriteFixture(t, false, "SubVegAXL_BC", 3)
	if result, err := NewTwoPageVegetationService(nil); result != nil || err == nil {
		t.Fatal("nil owner accepted", result, err)
	}
	service := vegetationFacade(t, contexts)
	raw := vegetationAttemptJSON(t, request)
	before := vprotest.DatabaseBytes(t, contexts.Projects.Sqlite.Attachments)
	for _, invalid := range []string{
		"", "null", `{}`, strings.Replace(raw, `"requestId":`, `"unexpected":`, 1),
		strings.Replace(raw, `"requestId":`, `"requestId":"b0cbfa00-1234-4123-8123-000000000009","requestId":`, 1),
		strings.Replace(raw, `"requestId":`, `"\u0072equestId":"b0cbfa00-1234-4123-8123-000000000009","requestId":`, 1),
	} {
		if result, err := service.Save(context.Background(), state.ContextID, invalid); result != nil || err == nil {
			t.Fatal("malformed/duplicate/escaped transport granted writer", result, err)
		}
		if result, err := service.RecoverOutcome(context.Background(), state.ContextID, invalid); result != nil || err == nil {
			t.Fatal("malformed transport granted certificate", result, err)
		}
	}
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	for _, ctx := range []context.Context{nil, cancelled} {
		if result, err := service.Save(ctx, state.ContextID, raw); result != nil || err == nil ||
			ctx != nil && !errors.Is(err, context.Canceled) {
			t.Fatal("nil/cancelled facade writer granted", result, err)
		}
		if result, err := service.RecoverOutcome(ctx, state.ContextID, raw); result != nil || err == nil {
			t.Fatal("nil/cancelled facade recovery granted", result, err)
		}
	}
	for _, facade := range []*TwoPageVegetationService{nil, {}} {
		if result, err := facade.Save(context.Background(), state.ContextID, raw); result != nil || err == nil {
			t.Fatal("unowned facade accepted writer", result, err)
		}
	}
	if len(twoPageVegAttempts(contexts).Requests) != 0 ||
		!reflect.DeepEqual(before, vprotest.DatabaseBytes(t, contexts.Projects.Sqlite.Attachments)) {
		t.Fatal("strict/pre-cancel denial created an attempt or changed physical data")
	}
}

func TestTwoPageVegetationServiceExportedRPCContractAndStaleContextRejection(t *testing.T) {
	serviceType := reflect.TypeOf((*TwoPageVegetationService)(nil))
	wantMethods := []string{
		"CreateRow",
		"DeleteRow",
		"GetOriginal",
		"GetSpeciesReferences",
		"ListDeletedRows",
		"RecoverOutcome",
		"RecoverReceipt",
		"RestoreRow",
		"Save",
	}
	gotMethods := make([]string, 0, serviceType.NumMethod())
	for i := 0; i < serviceType.NumMethod(); i++ {
		m := serviceType.Method(i)
		gotMethods = append(gotMethods, m.Name)
		mt := m.Type
		for p := 1; p < mt.NumIn(); p++ {
			if kind := mt.In(p).Kind(); kind == reflect.Func || kind == reflect.Chan {
				t.Fatalf("TwoPageVegetationService.%s parameter %d has non-RPC kind %s", m.Name, p, kind)
			}
		}
		for r := 0; r < mt.NumOut(); r++ {
			if kind := mt.Out(r).Kind(); kind == reflect.Func || kind == reflect.Chan {
				t.Fatalf("TwoPageVegetationService.%s return %d has non-RPC kind %s", m.Name, r, kind)
			}
		}
	}
	if !reflect.DeepEqual(gotMethods, wantMethods) {
		t.Fatalf("TwoPageVegetationService exported method set = %v, want %v", gotMethods, wantMethods)
	}

	contexts, _, _, request := vegetationWriteFixture(t, false, "SubVegAXL_BC", 3)
	service := vegetationFacade(t, contexts)
	raw := vegetationAttemptJSON(t, request)
	ctx := context.Background()
	if _, err := service.GetOriginal(ctx, "stale-context-id", "108050", "SubVegAXL_BC"); err == nil {
		t.Fatal("expected stale context ID rejection on GetOriginal")
	}
	if _, err := service.GetSpeciesReferences(ctx, "stale-context-id", "108050", "SubVegAXL_BC"); err == nil {
		t.Fatal("expected stale context ID rejection on GetSpeciesReferences")
	}
	if _, err := service.Save(ctx, "stale-context-id", raw); err == nil {
		t.Fatal("expected stale context ID rejection on Save")
	}
	if _, err := service.ListDeletedRows(ctx, "stale-context-id", "108050", "SubVegAXL_BC"); err == nil {
		t.Fatal("expected stale context ID rejection on ListDeletedRows")
	}
}
