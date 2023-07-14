package avataaars

import (
	"os"
	"strconv"
	"time"
	
	log "github.com/sirupsen/logrus"
	"github.com/onflow/cadence"
	"github.com/onflow/flow-go-sdk"
	"github.com/onflow/flow-go-sdk/access"
	"github.com/onflow/flow-go-sdk/crypto"
	"golang.org/x/net/context"
)

const (
	EnvTransactorAddress    = "TRANSACTOR_ADDRESS"
	EnvTransactorPrivateKey = "TRANSACTOR_PK"
	EnvTransactorKeyIndex   = "TRANSACTOR_KEY_INDEX"
)

type Transactor struct {
	Address    string `json:"address"`
	PrivateKey string `json:"privateKey"`
	KeyIndex   int64  `json:"keyIndex"`
}

func (t Transactor) ExecuteTransaction(script string, args []cadence.Value, c access.Client) (txID flow.Identifier, err error) {
	ctx := context.Background()
	block, err := c.GetLatestBlock(ctx, true)

	addr, key, signer, err := t.getAccountInfo(c)
	if err != nil {
		return
	}

	tx := flow.NewTransaction().
		SetScript([]byte(script)).
		SetProposalKey(addr, key.Index, key.SequenceNumber).
		SetReferenceBlockID(block.ID).
		AddAuthorizer(addr).
		SetPayer(addr)
	for _, a := range args {
		tx.AddArgument(a)
	}

	err = tx.SignEnvelope(addr, key.Index, signer)
	if err != nil {
		return
	}

	err = c.SendTransaction(ctx, *tx)
	if err != nil {
		return
	}

	txID = tx.ID()
	return
}

func (t Transactor) getAccountInfo(c access.Client) (address flow.Address, key *flow.AccountKey, signer crypto.Signer, err error) {
	privateKey, err := crypto.DecodePrivateKeyHex(crypto.ECDSA_P256, t.PrivateKey)
	if err != nil {
		return
	}

	a := flow.HexToAddress(t.Address)
	acc, err := c.GetAccount(context.Background(), a)
	if err != nil {
		return
	}
	accountKey := acc.Keys[t.KeyIndex]
	s, err := crypto.NewInMemorySigner(privateKey, accountKey.HashAlgo)
	if err != nil {
		return
	}

	return a, accountKey, s, nil
}

type Provider interface {
	GetTransactor() (transactor Transactor, err error)
}

type EnvProvider struct {
	transactor Transactor
}

func (e EnvProvider) GetTransactor() (transactor Transactor, err error) {
	return e.transactor, nil
}

func NewEnvProvider() (p EnvProvider) {
	var t Transactor
	t.Address = os.Getenv(EnvTransactorAddress)
	t.PrivateKey = os.Getenv(EnvTransactorPrivateKey)
	if keyIndexRaw, ok := os.LookupEnv(EnvTransactorKeyIndex); ok {
		t.KeyIndex, _ = strconv.ParseInt(keyIndexRaw, 10, 32)
	}

	p = EnvProvider{transactor: t}
	return
}

func WaitForSeal(ctx context.Context, c access.Client, id flow.Identifier, pollInterval time.Duration) (r *flow.TransactionResult, err error) {
	r, err = c.GetTransactionResult(ctx, id)
	if err != nil {
		return
	}

	logger := log.WithFields(log.Fields{"transactionID": id.String()})
	logger.Info("Waiting for transaction to be sealed")

	for r.Status != flow.TransactionStatusSealed {
		logger.Debug("waiting for transaction seal...")
		time.Sleep(pollInterval)
		r, err = c.GetTransactionResult(ctx, id)
		if err != nil {
			return
		}
	}

	return
}
