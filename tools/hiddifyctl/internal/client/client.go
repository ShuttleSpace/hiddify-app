package client

import (
	"context"
	"net/url"
	"time"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/grpc/hcommon"
	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/grpc/hcore"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// Client is a thin gRPC client for the hiddify-core `Core` service that listens
// on 127.0.0.1:17078 (plaintext, no auth) while the app (or a standalone core)
// is running.
type Client struct {
	conn *grpc.ClientConn
	core hcore.CoreClient
}

// Dial connects to the core gRPC endpoint, blocking until reachable or the
// timeout elapses.
func Dial(addr string, timeout time.Duration) (*Client, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	conn, err := grpc.DialContext(ctx, addr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
	)
	if err != nil {
		return nil, err
	}
	return &Client{conn: conn, core: hcore.NewCoreClient(conn)}, nil
}

// Close releases the underlying connection.
func (c *Client) Close() error {
	return c.conn.Close()
}

// CoreState reads the current core state from the CoreInfoListener stream (the
// server immediately sends the current state as the first message).
func (c *Client) CoreState(ctx context.Context) (hcore.CoreStates, error) {
	sctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	stream, err := c.core.CoreInfoListener(sctx, &hcommon.Empty{})
	if err != nil {
		return hcore.CoreStates_STOPPED, err
	}
	info, err := stream.Recv()
	if err != nil {
		return hcore.CoreStates_STOPPED, err
	}
	return info.CoreState, nil
}

// Start connects using a config path (e.g. an active profile's <id>.json). A
// core that is already started is treated as success.
func (c *Client) Start(ctx context.Context, configPath, name string, disableMem bool) error {
	res, err := c.core.Start(ctx, &hcore.StartRequest{
		ConfigPath:         configPath,
		ConfigName:         name,
		DisableMemoryLimit: disableMem,
	})
	if err != nil {
		return err
	}
	switch res.MessageType {
	case hcore.MessageType_ALREADY_STARTED, hcore.MessageType_EMPTY:
		return nil
	default:
		if res.CoreState == hcore.CoreStates_STARTED {
			return nil
		}
		return &Error{msg: "start failed: " + res.Message}
	}
}

// Stop disconnects the core.
func (c *Client) Stop(ctx context.Context) error {
	_, err := c.core.Stop(ctx, &hcommon.Empty{})
	return err
}

// Status returns the combined core state and live system info.
func (c *Client) Status(ctx context.Context) (*Status, error) {
	sys, err := c.core.GetSystemInfo(ctx, &hcommon.Empty{})
	if err != nil {
		return nil, err
	}
	state, err := c.CoreState(ctx)
	if err != nil {
		return nil, err
	}
	// GetSystemProxyStatus is optional on older cores; a failure or a hang
	// must not break the whole status command, so bound it with a short timeout.
	systemProxy := false
	spCtx, spCancel := context.WithTimeout(ctx, 2*time.Second)
	if sp, spErr := c.SystemProxyEnabled(spCtx); spErr == nil {
		systemProxy = sp
	}
	spCancel()
	return &Status{
		State:            state.String(),
		CurrentProfile:   unescape(sys.CurrentProfile),
		CurrentOutbound:  unescape(sys.CurrentOutbound),
		Uplink:           sys.Uplink,
		Downlink:         sys.Downlink,
		UplinkTotal:      sys.UplinkTotal,
		DownlinkTotal:    sys.DownlinkTotal,
		TrafficAvailable: sys.TrafficAvailable,
		SystemProxy:      systemProxy,
	}, nil
}

// unescape decodes a (possibly percent-encoded) core string such as a profile
// or node name. Non-encoded strings are returned unchanged.
func unescape(s string) string {
	if decoded, err := url.PathUnescape(s); err == nil {
		return decoded
	}
	return s
}

// Error is returned when the core rejects a request.
type Error struct{ msg string }

func (e *Error) Error() string { return e.msg }
