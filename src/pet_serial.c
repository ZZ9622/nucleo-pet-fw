#include "pet_serial.h"
#include "stm32f401xe_minimal.h"
#include <stddef.h>
typedef struct { volatile uint32_t SR,DR,BRR,CR1,CR2,CR3,GTPR; } Uart;
#define UART2 ((Uart *)0x40004400UL)
#define APB1ENR (*(volatile uint32_t *)0x40023840UL)
#define RING 2048U
static volatile uint32_t head,tail,tx_count,tx_sent;
static volatile bool overflow;
static char rx[RING],tx[1536],line[1024];
static unsigned used,count;
static uint32_t identity[4];
void USART2_IRQHandler(void);
void USART2_IRQHandler(void)
{
    uint32_t sr=UART2->SR;
    if(sr&((1U<<5)|(1U<<3))) {
        uint32_t byte=UART2->DR;
        uint32_t next=(head+1U)%RING;
        if((sr&15U)||next==tail) { overflow=true; }
        else { rx[head]=(char)byte; head=next; }
    }
    if((UART2->CR1&(1U<<7)) && (sr&(1U<<7))) {
        if(tx_sent<tx_count) { UART2->DR=(uint8_t)tx[tx_sent++]; }
        else { UART2->CR1&=~(1U<<7); }
    }
}
static void append(const char *s) { while(*s && count<sizeof tx-1) { tx[count++]=*s++; } }
static void number(uint32_t n) {
    char d[10]; unsigned k=0; do {d[k++]=(char)('0'+n%10);n/=10;}while(n);
    while(k && count<sizeof tx-1) {tx[count++]=d[--k];}
}
static void hex(uint32_t n) { for(int i=7;i>=0;--i) { char s[2]={"0123456789abcdef"[(n>>(i*4))&15U],0};append(s); } }
static void id(const uint32_t w[4]) {for(unsigned i=0;i<4;++i) {hex(w[i]);}}
static bool equal(const char *a,const char *b) {while(*a && *a==*b){++a;++b;}return *a==*b;}
static bool parse(const char *s,uint32_t *out,unsigned base,unsigned length) {
    uint32_t n=0;unsigned k=0;
    while(*s) {unsigned d=(unsigned)(*s>='0'&&*s<='9'?*s-'0':*s>='a'&&*s<='f'?*s-'a'+10:99);
        if(d>=base || n>(0xFFFFFFFFU-d)/base) {return false;}n=n*base+d;++s;++k;}
    if(!k || (length && k!=length)){return false;}*out=n;return true;
}
static bool parse_id(char *s,uint32_t w[4]) {
    unsigned len=0;while(s[len]){++len;}if(len!=32){return false;}
    for(unsigned i=0;i<4;++i){char tmp[9];for(unsigned j=0;j<8;++j){tmp[j]=s[i*8+j];}tmp[8]=0;
        if(!parse(tmp,&w[i],16,8)){return false;}}return true;
}
static void response(PetHandoff *h,const char *request,const char *error) {
    count=0;append("{\"v\":2,\"requestID\":\"");append(request);append("\",\"ok\":");append(error?"false":"true");
    append(",\"error\":\"");append(error?error:"");append("\",\"petID\":\"");id(identity);
    append("\",\"phase\":");number(h->fault?PET_LOCKED:h->phase);append(",\"revision\":");number(h->revision);
    append(",\"transferID\":\"");id(h->transaction);append("\",\"payloadHash\":");number(h->payload_hash);
    append(",\"state\":[");uint32_t w[PET_STATE_WORDS];pet_state_encode(&h->pet,w);
    for(unsigned i=0;i<PET_STATE_WORDS;++i){if(i){append(",");}number(w[i]);}append("]}");
    uint32_t crc=pet_crc32(tx,count);append("|");hex(crc);append("\n");
    tx_sent=0;tx_count=count;UART2->CR1|=1U<<7;
}
static void process(PetHandoff *h) {
    char *fields[7];unsigned n=0;fields[n++]=line;
    for(unsigned i=0;line[i];++i){if(line[i]=='|'){line[i]=0;if(n==7){return;}fields[n++]=&line[i+1];}}
    if(n!=7 || fields[0][0]!='!'){return;}
    /* Restore delimiters for checksum, then split again. */
    uint32_t supplied; if(!parse(fields[6],&supplied,16,8)){return;}
    size_t size=(size_t)(fields[6]-line-1);
    for(unsigned i=1;i<6;++i){fields[i][-1]='|';}
    bool valid=pet_crc32(line,size)==supplied;
    for(unsigned i=1;i<6;++i){fields[i][-1]=0;}
    uint32_t req[4],petid[4],transaction[4],revision;
    if(!valid || !parse_id(fields[0]+1,req) || !parse_id(fields[2],petid) ||
       !parse_id(fields[3],transaction) || !parse(fields[4],&revision,10,0)){return;}
    const char *error=0;
    if(!equal(fields[1],"STATUS")) {
        for(unsigned i=0;i<4;++i){if(petid[i]!=identity[i]){error="wrong_pet";}}
        PetState incoming;PetState *candidate=0;
        if(equal(fields[1],"RETURN_STAGE")) {
            uint32_t w[PET_STATE_WORDS];char *p=fields[5];
            for(unsigned i=0;i<PET_STATE_WORDS;++i){char *end=p;while(*end && *end!=','){++end;}
                bool more=*end==',';*end=0;
                if(!parse(p,&w[i],10,0)||more!=(i<PET_STATE_WORDS-1)){error="invalid_state";break;}p=end+1;}
            if(!error){if(!pet_state_decode(&incoming,w)){error="invalid_state";}else{candidate=&incoming;}}
        } else if(*fields[5]) {error="invalid_request";}
        if(!error){error=pet_handoff_command(h,fields[1],transaction,revision,candidate);}
    }
    response(h,fields[0]+1,error);
}
void pet_serial_init(void) {
    GPIOA->MODER=(GPIOA->MODER&~0xF0UL)|0xA0UL;
    GPIOA->AFR[0]=(GPIOA->AFR[0]&~0xFF00UL)|0x7700UL;
    GPIOA->PUPDR=(GPIOA->PUPDR&~0xF0UL)|0x40UL;
    for(unsigned i=0;i<3;++i){identity[i]=((volatile const uint32_t *)0x1FFF7A10UL)[i];}identity[3]=1;
    APB1ENR|=1UL<<17;(void)APB1ENR;
    UART2->CR1=0;UART2->BRR=139;UART2->CR2=0;UART2->CR3=0;
    UART2->CR1=(1U<<13)|(1U<<3)|(1U<<2)|(1U<<5);
    (*(volatile uint32_t *)0xE000E104UL)=1U<<6;
}
void pet_serial_poll(PetHandoff *h) {
    if(overflow){tail=head;used=0;overflow=false;return;}
    if(tx_sent<tx_count || (UART2->CR1&(1U<<7))){return;}
    while(tail!=head){char c=rx[tail];tail=(tail+1U)%RING;
        if(c=='\n'){line[used]=0;process(h);used=0;return;}
        if(c=='!'){used=0;}
        if(used<sizeof line-1){line[used++]=c;}else{used=0;}
    }
}
