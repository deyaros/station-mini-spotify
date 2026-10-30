// alice-say: make Alice say a text in her own voice (cloud TTS, the speaker's
// own authorization) through her local IPC on 127.0.0.1:9875.
// Request format from the hackalice wiki (recipes/sounds.md#native-tts,
// contrib/alice-say.py): Remoting -> AliceCapability, method START_VOCALIZE
// (18) with TVocalizeDirective{text, mode=Append}.
// usage: alice-say "text"
#include <arpa/inet.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define MAX_TEXT 2000

typedef struct {
  uint8_t data[MAX_TEXT + 256];
  size_t len;
} buf_t;

static void put_varint(buf_t *b, uint64_t v) {
  do {
    uint8_t byte = v & 0x7f;
    v >>= 7;
    b->data[b->len++] = byte | (v ? 0x80 : 0);
  } while (v);
}

static void put_int(buf_t *b, uint32_t field, uint64_t value) {
  put_varint(b, (uint64_t)field << 3);
  put_varint(b, value);
}

static void put_bytes(buf_t *b, uint32_t field, const void *p, size_t n) {
  put_varint(b, ((uint64_t)field << 3) | 2);
  put_varint(b, n);
  memcpy(b->data + b->len, p, n);
  b->len += n;
}

int main(int argc, char **argv) {
  if (argc != 2 || !argv[1][0] || strlen(argv[1]) > MAX_TEXT) {
    fprintf(stderr, "usage: alice-say TEXT (up to %d bytes)\n", MAX_TEXT);
    return 2;
  }
  const char *text = argv[1];
  static const char cap[] = "AliceCapability";
  buf_t directive = {0}, method = {0}, remote = {0}, env = {0};

  put_bytes(&directive, 1, text, strlen(text));
  put_int(&directive, 2, 1);                       // mode: Append
  put_int(&method, 1, 18);                         // START_VOCALIZE
  put_int(&method, 3, 1);                          // events
  put_bytes(&method, 13, directive.data, directive.len);
  put_bytes(&remote, 7, cap, sizeof(cap) - 1);
  put_bytes(&remote, 8, method.data, method.len);
  put_bytes(&env, 252, remote.data, remote.len);   // QuasarMessage.remoting
  put_int(&env, 253, 210);

  uint8_t hdr[4] = {env.len & 0xff, env.len >> 8 & 0xff, env.len >> 16 & 0xff, env.len >> 24};
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons(9875)};
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (fd < 0 || connect(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
    perror("alice-say: connect 127.0.0.1:9875");
    return 1;
  }
  if (write(fd, hdr, 4) != 4 || write(fd, env.data, env.len) != (ssize_t)env.len) {
    perror("alice-say: write");
    return 1;
  }
  usleep(300 * 1000);  // let Quasar read the request before the socket closes
  close(fd);
  return 0;
}
