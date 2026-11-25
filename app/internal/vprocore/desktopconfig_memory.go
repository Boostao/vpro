package vprocore

import (
	"errors"

	"go.yaml.in/yaml/v3"
)

// NewInMemoryDesktopConfig initializes an isolated, strictly in-memory DesktopConfig
// from baseYAML (defaulting to DesktopDefaults when baseYAML is empty).
// Reads and updates never touch disk, enabling per-session web report preferences.
func NewInMemoryDesktopConfig(baseYAML []byte) (*DesktopConfig, error) {
	source := baseYAML
	if len(source) == 0 {
		source = DesktopDefaults
	}
	values, err := DecodeConfig(source)
	if err != nil {
		return nil, err
	}
	NormalizeLegacyConfigScalars(values)
	if _, present := values["Desktop"]; !present {
		values["Desktop"] = map[string]any{}
	}
	desktop, err := ConfigSection(values, "Desktop")
	if err != nil {
		return nil, err
	}
	if _, present := desktop["SchemaVersion"]; !present {
		desktop["SchemaVersion"] = 1
	}
	if _, err := ConfigInt(values, "Desktop", "SchemaVersion", 1, 1); err != nil {
		return nil, err
	}
	if err := mergeConfigDefaults(values); err != nil {
		return nil, err
	}
	if err := ValidateDesktopConfig(values); err != nil {
		return nil, err
	}
	encoded, err := yaml.Marshal(values)
	if err != nil {
		return nil, err
	}
	return &DesktopConfig{
		memoryOnly:  true,
		memoryBytes: encoded,
	}, nil
}

// CloneInMemory returns an independent in-memory copy of c without mutating c or writing to disk.
// Works for both memory-backed and disk-backed DesktopConfig instances.
func (c *DesktopConfig) CloneInMemory() (*DesktopConfig, error) {
	if c == nil {
		return nil, errors.New("desktop configuration is unavailable")
	}
	c.Mu.Lock()
	defer c.Mu.Unlock()

	values, err := c.ReadLocked()
	if err != nil {
		return nil, err
	}
	var cloned []byte
	if c.memoryOnly {
		cloned = make([]byte, len(c.memoryBytes))
		copy(cloned, c.memoryBytes)
	} else {
		cloned, err = yaml.Marshal(values)
		if err != nil {
			return nil, err
		}
	}
	return &DesktopConfig{
		memoryOnly:  true,
		memoryBytes: cloned,
	}, nil
}

// IsMemoryOnly reports whether c stores configuration strictly in memory without disk I/O.
func (c *DesktopConfig) IsMemoryOnly() bool {
	return c != nil && c.memoryOnly
}
