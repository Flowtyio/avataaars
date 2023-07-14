package templates

import (
	_ "embed"
)

//go:embed transactions/save_content.cdc
var TxnSaveContent string
