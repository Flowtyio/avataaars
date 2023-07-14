package main

import (
	"encoding/json"
	"flag"
	"golang.org/x/net/context"
	"io/ioutil"
	"strings"
	"text/template"
	"time"

	"github.com/onflow/cadence"
	"github.com/onflow/flow-go-sdk/access"
	"github.com/onflow/flow-go-sdk/access/grpc"
	log "github.com/sirupsen/logrus"

	"Flowtyio/avataaars"
	"Flowtyio/avataaars/templates"
)

var (
	partsFilePath string
	network       string
)

type Part struct {
	Name    string   `json:"name"`
	Content []string `json:"content"`
}

func registerParts(parts map[string][]Part, client access.Client, transactor avataaars.Transactor) {
	contractAddress := ""
	switch network {
	case "emulator":
		contractAddress = "0xf8d6e0586b0a20c7"
	case "testnet":
		contractAddress = "0xfcd1f9be4cc5e47b"
	case "mainnet":
		contractAddress = "0xc934ed0c0f4788bc"
	}
	txnContent := format(templates.TxnSaveContent, map[string]interface{}{
		"contractAddress": contractAddress,
	})

	for section, ps := range parts {
		log.WithField("section", section).Info("registering content for part")
		for _, part := range ps {
			args := make([]cadence.Value, 0)
			args = append(args, cadence.String(section))
			args = append(args, cadence.String(part.Name))

			content := make([]cadence.Value, 0)
			for _, c := range part.Content {
				content = append(content, cadence.String(c))
			}
			args = append(args, cadence.NewArray(content))

			txID, err := transactor.ExecuteTransaction(txnContent, args, client)
			if err != nil {
				panic(err)
			}

			log.WithField("txID", txID.String()).Info("transaction executed")
			result, err := avataaars.WaitForSeal(context.Background(), client, txID, time.Second)
			if err != nil {
				log.WithError(err).Fatal("failed waiting for a transaction to be sealed")
			}

			if result.Error != nil {
				log.WithError(result.Error).Fatal("transaction failed")
			}
		}
	}
}

func main() {
	flag.Parse()
	var (
		client access.Client
		err    error
	)

	switch network {
	case "emulator":
		client, err = grpc.NewClient(grpc.EmulatorHost)
		break
	case "testnet":
		client, err = grpc.NewClient(grpc.TestnetHost)
		break
	case "mainnet":
		client, err = grpc.NewClient(grpc.MainnetHost)
		break
	default:
		panic("invalid network")
	}

	if err != nil {
		panic(err)
	}
	data, err := ioutil.ReadFile(partsFilePath)
	if err != nil {
		panic(err)
	}

	var parts map[string][]Part
	err = json.Unmarshal(data, &parts)
	if err != nil {
		panic(err)
	}

	provider := avataaars.NewEnvProvider()
	transactor, err := provider.GetTransactor()
	if err != nil {
		panic(err)
	}

	registerParts(parts, client, transactor)
}

func format(s string, v interface{}) string {
	t, b := new(template.Template), new(strings.Builder)
	template.Must(t.Parse(s)).Execute(b, v)
	return b.String()
}

func init() {
	flag.StringVar(&partsFilePath, "parts", "", "Path to the parts file")
	flag.StringVar(&network, "network", "emulator", "The flow network to connect to")
}
