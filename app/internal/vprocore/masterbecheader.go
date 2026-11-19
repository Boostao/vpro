package vprocore

import (
	"github.com/boostao/vpro/app/internal/sqlutil"
)

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"unicode/utf8"
)

// UserAccreditation describes the active user's BEC master and USysUserRestrictions status.
type UserAccreditation struct {
	UserName           string `json:"userName"`
	Accredited         bool   `json:"accredited"`
	MasterBECAllowed   bool   `json:"masterBecAllowed"`
	InUserRestrictions bool   `json:"inUserRestrictions"`
	CanEditBECSiteUnit bool   `json:"canEditBecSiteUnit"`
}

func MasterBECAllowed(user string) bool {
	return strings.EqualFold(user, "Will MacKenzie")
}

func (s *PlotService) CanEditMasterBEC() bool {
	s.Mu.RLock()
	defer s.Mu.RUnlock()
	return MasterBECAllowed(s.CurrentUser)
}

// LookupUserAccreditation checks whether user matches the master BEC authorizer or appears in
// VPro64.USysUserRestrictions, always preserving the BECSiteUnit lock unless master-authorized.
func (c *SqliteContext) LookupUserAccreditation(ctx context.Context, user string) (UserAccreditation, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return UserAccreditation{}, err
	}
	if !utf8.ValidString(user) {
		return UserAccreditation{}, errors.New("user name contains malformed Unicode")
	}
	master := MasterBECAllowed(user)
	status := UserAccreditation{
		UserName:           user,
		MasterBECAllowed:   master,
		CanEditBECSiteUnit: master,
		Accredited:         master,
	}
	if c == nil || user == "" {
		return status, nil
	}
	if err := sqlutil.AcquireMutexLease(ctx, &c.mu); err != nil {
		return UserAccreditation{}, err
	}
	defer c.mu.Unlock()
	if c.conn == nil {
		return UserAccreditation{}, errors.New("project context is closed")
	}
	var tableExists bool
	if err := c.conn.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM "VPro64".sqlite_master WHERE type='table' AND name='USysUserRestrictions' COLLATE BINARY)`).Scan(&tableExists); err != nil {
		return status, nil
	}
	if !tableExists {
		return status, nil
	}
	var inRestrictions bool
	err := c.conn.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM "VPro64"."USysUserRestrictions" WHERE typeof("UserName")='text' AND "UserName" COLLATE NOCASE = ?)`, user).Scan(&inRestrictions)
	if err == nil && inRestrictions {
		status.InUserRestrictions = true
		status.Accredited = true
	}
	return status, nil
}

// UserAccreditationStatus evaluates DesktopConfig/PlotService user accreditation against VPro64.
func (s *PlotService) UserAccreditationStatus(ctx context.Context) (UserAccreditation, error) {
	if s == nil {
		return UserAccreditation{}, errors.New("plot service is unavailable")
	}
	s.Mu.RLock()
	user := s.CurrentUser
	projects := s.Projects
	s.Mu.RUnlock()
	if user == "" && projects != nil && projects.Preferences != nil {
		if cfgUser, err := projects.Preferences.UserName(); err == nil {
			user = cfgUser
		}
	}
	var sqliteCtx *SqliteContext
	if projects != nil {
		projects.Mu.RLock()
		sqliteCtx = projects.Sqlite
		projects.Mu.RUnlock()
	}
	if sqliteCtx == nil {
		master := MasterBECAllowed(user)
		return UserAccreditation{
			UserName:           user,
			Accredited:         master,
			MasterBECAllowed:   master,
			CanEditBECSiteUnit: master,
		}, nil
	}
	return sqliteCtx.LookupUserAccreditation(ctx, user)
}

var _ = sql.ErrNoRows

func masterBECHeaderField(h FS882Header) BecHeaderField {
	return BecHeaderField{"BECSiteUnit", "becSiteUnit", "Admin", 100, h.BECSiteUnit}
}

func validateMasterBECHeaderValues(h FS882Header, old *FS882Header, allowed bool) error {
	if old != nil && SameSiteCode(h.BECSiteUnit, old.BECSiteUnit) {
		return nil
	}
	if old == nil && h.BECSiteUnit == nil {
		return nil
	}
	if !allowed {
		return errors.New("BEC Master editing is restricted to the source-authorized user; use Working Unit instead")
	}
	return sqlutil.ValidateSiteCodeText("BECSiteUnit", h.BECSiteUnit, 100)
}

func (s *PlotService) validateMasterBECRestoreValue(table, column string, value any) error {
	if table != "Admin" || column != "BECSiteUnit" {
		return nil
	}
	if !s.CanEditMasterBEC() {
		return errors.New("BEC Master restoration is restricted to the source-authorized user")
	}
	return validateCodeRestoreValue(table, column, value, []BecHeaderField{masterBECHeaderField(FS882Header{})})
}
