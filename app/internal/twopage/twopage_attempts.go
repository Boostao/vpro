package twopage

import (
	"encoding/json"
	"errors"
	"reflect"
	"sync"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type twoPageSoilAttempt struct {
	request any
	Active  int
	Sealed  bool
}

type twoPageSoilAttemptLedger struct {
	Mu       sync.Mutex
	Requests map[string]*twoPageSoilAttempt
}

func (ledger *twoPageSoilAttemptLedger) Entry(requestID string, request any) (*twoPageSoilAttempt, error) {
	if ledger.Requests == nil {
		ledger.Requests = map[string]*twoPageSoilAttempt{}
	}
	if existing := ledger.Requests[requestID]; existing != nil {
		if !reflect.DeepEqual(existing.request, request) {
			return nil, errors.New("two-page soil UUID already belongs to another exact request payload")
		}
		return existing, nil
	}
	entry := &twoPageSoilAttempt{request: request}
	ledger.Requests[requestID] = entry
	return entry, nil
}

func twoPageSoilAttempts(s *vprocore.ContextService) *twoPageSoilAttemptLedger {
	return vprocore.ContextState(s, func() *twoPageSoilAttemptLedger {
		return &twoPageSoilAttemptLedger{}
	})
}

type twoPageVegetationAttempt struct {
	payload string
	Active  int
	Sealed  bool
}

type twoPageVegetationAttemptLedger struct {
	Mu       sync.Mutex
	Requests map[string]*twoPageVegetationAttempt
}

func (ledger *twoPageVegetationAttemptLedger) Entry(requestID string, request any) (*twoPageVegetationAttempt, error) {
	raw, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}
	payload := string(raw)
	if ledger.Requests == nil {
		ledger.Requests = map[string]*twoPageVegetationAttempt{}
	}
	if existing := ledger.Requests[requestID]; existing != nil {
		if existing.payload != payload {
			return nil, errors.New("two-page vegetation UUID already belongs to another exact request payload")
		}
		return existing, nil
	}
	entry := &twoPageVegetationAttempt{payload: payload}
	ledger.Requests[requestID] = entry
	return entry, nil
}

func twoPageVegAttempts(s *vprocore.ContextService) *twoPageVegetationAttemptLedger {
	return vprocore.ContextState(s, func() *twoPageVegetationAttemptLedger {
		return &twoPageVegetationAttemptLedger{}
	})
}
