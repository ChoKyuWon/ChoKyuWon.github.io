---
layout: post
title: \[번역] Escaping the Chrome Sandbox with RIDL
subtitle: RIDL을 사용하여 크롬 샌드박스 우회하기
tags: [번역]
comments: true
---

## 들어가기 전

이 글은 [Escaping the Chrome Sandbox with RIDL](https://https://googleprojectzero.blogspot.com/2020/02/escaping-chrome-sandbox-with-ridl.html)을 번역한 글입니다.

## Introduction
TL;DR: 프로세스간 메모리 릭 취액점은 크롬 샌드박스 탈출에 사용될 수 있습니다. 하지만 이런 샌드박스 탈출을 위해서는 공격자가 컴프로마이즈된 렌더러 프로세스를 가지고 있어야 합니다. 이러한 공격을 방지하기 위해서는 CPU의 마이크로코드를 최신의 상태로 유지하고 하이퍼스레딩을 꺼야 합니다.  
예전의 블로그 포스트 [Trashing the Flow of Data](https://googleprojectzero.blogspot.com/2019/05/trashing-flow-of-data.html)에서 크롬의 자바스크립트 엔진인 V8의 버그를 익스플로잇하여 렌더러 프로세스에서 임의 코드를 실행하는 방법에 대해 설명했습니다. 이 익스플로잇이 유용하기 위해서는 두번째 익스플로잇이 필요합니다. 왜냐하면 크롬 샌드박스가 [site isolation](https://www.chromium.org/Home/chromium-security/site-isolation)을 통해 다른 렌더러로의 접근을 막고, 또한 OS로의 접근 역시 제한하기 때문입니다.  
  
  
이 포스트는 RIDL과 그 비슷한 류의 하드웨어 취약점이 컴프로마이즈된 렌더러에서 사용될 때 샌드박스에 끼치는 영향에 대해 알아보겠습니다. 크롬의 IPC(Inter Process Comunication)인 Mojo는 메세지 라우팅을 비밀 값에 기반하여 수행합니다. 이 비밀 값의 유출은 공격자에게 권한이 높은 인터페이스에 메세지를 보내서 렌더러에게 허용되지 않은 행동을 수행하게 할 수 있습니다. 이를 사용하여 샌드박스의 바깥에서 .bat 파일을 실행한 것처럼 임의적인 로컬 파일을 읽을 수 있습니다. 이 글을 쓰는 시점에, Apple과 Microsoft 모두 현재 크롬 시큐리티 팀과 협동하여 이 이슈를 수정하고 있습니다.  
## Background
크롬 프로세스 모델을 간략화 하면 다음과 같습니다:  
![Chrome_process_model](https://lh3.googleusercontent.com/-yYhUafj7Km0tsJ6wpPoQgdiGYALjmKXcwyt3WN_7SMIuidrotWghXewF2PuU0tBoDKixaz_W_kilwGiwSaeE6YGcOr7wFNEqqPT_H0IiZ4IeH2zTgnEISFy40k3252n9AUSKUS4)  
The renderer processes are in separate sandboxes and the access to the kernel is limited, e.g. via a seccomp filter on Linux or  win32k lockdown on Windows.
렌더러 프로세스는 샌드박스에 의해 격리되어 있어 커널로의 접근이 제한되어 있습니다. (리눅스에서는 seccomp filter, 윈도우에서는 [win32 lockdown](https://googleprojectzero.blogspot.com/2016/11/breaking-chain.html) 같은 기법을 사용하여 샌드박스를 구현합니다.) 그 대신 렌더러가 뭔가 필요하면 다른 프로세스에게 다양한 행동을 수행하도록 요청할 수 있습니다. 예를 들어, 이미지를 로드하기 위해서 렌더러 프로세스는 네트워크 서비스에게 이미지를 가져오라고 요청해야 합니다.  
  
  
The default mechanism for inter process communication in Chrome is called Mojo.
크롬에서 프로세스간 통신을 위한 기본적인 메커니즘은 Mojo라고 불립니다. 기본적으로 메세지/데이터 파이프와 공유 메모리를 지원하지만 C++, Java, JavaScript 등의 고급 언어 바인딩을 주로 사용합니다. 즉 커스텀 IDL(Interface Deficnition Language) 인터페이스를 만든다면 Mojo가 대부분을 선택된 언어를 위해 생성하고, 당신은 이에 대한 기능만 구현하면 됩니다.
이를 실제로 확인해보려면 **.mojom IDL** 안의 ``[URLLoaderFactory](https://cs.chromium.org/chromium/src/services/network/public/mojom/url_loader_factory.mojom?l=32&rcl=85c4d882d30b93f615011b036176cd0ce5b791df)``와 [C++ 구현체](https://cs.chromium.org/chromium/src/services/network/url_loader_factory.h?l=43&rcl=5fa80058135430d5253d4f2912a3bb11c6ecbfa9), 그리고 [렌더러 프로세스 Usage](https://cs.chromium.org/chromium/src/services/network/cors/cors_url_loader.cc?l=513&rcl=5fa80058135430d5253d4f2912a3bb11c6ecbfa9)에서 확인할 수 있습니다.

> 원문: Under the hood it supports message/data pipes and shared memory but you would usually use one of the higher level language bindings in C++, Java or JavaScript. That is, you create an interface with methods in a custom interface definition language (IDL), Mojo generates stubs for you in your language of choice and you just implement the functionality.
> 이에 대한 더 나은 번역이 있다면 제보 바랍니다.

One notable feature is that Mojo allows you to forward IPC endpoints over an existing channel.
한가지 주목해야 할 것은 Mojo가 이미 존재하는 채널에 당신의 IPC 종단을 전달할 수 있게 허용하는 것입니다.(?)
This is used extensively in the Chrome codebase, i.e. whenever you see a pending_receiver or pending_remote parameter in a .mojom file.
이것은 크롬 코드베이스에서 광범위하게 사용되고 있습니다. .mojo 파일에서 ``pending_reciver`` 또는 ``pending_remote`` 매개변수를 본다면, 이 기법을 사용중인것입니다.  
![chrome](https://lh5.googleusercontent.com/31XSD4o22C2IhMCxB1hz_JZ5xoIMb7EskVpAPPoKzRYXDEU2vEoe3MT2t0FfrCrvpUlFpI3LJJdpd2nbRlJLfEtVn7RhH1AB0WG3Zwydtc6Hyafo1MoX4c1kvQub9Rze8rWtvn5M)  
  
Under the hood, Mojo uses a platform specific message pipe between processes, or more specifically between nodes in Mojo.
Two nodes can be connected directly with each other but they don’t have to since Mojo supports message routing.
One node in the network is called the broker node which has some additional responsibilities to set up node channels and perform some actions restricted by the sandbox.

The IPC endpoints themselves are called ports.
In the URLLoaderFactory example above, both the client and the implementation side are identified by a port.
In code, a port looks like [this](https://cs.chromium.org/chromium/src/mojo/core/ports/port.h?l=64&rcl=20c48eee7403759d676e5d3a125657aaba1a03ca):
```C++
class Port : public base::RefCountedThreadSafe<Port> {
 public:
  // [...]
  // The current State of the Port.
  State state;
  // The Node and Port address to which events should be routed FROM this Port.
  // Note that this is NOT necessarily the address of the Port currently sending
  // events TO this Port.
  NodeName peer_node_name;
  PortName peer_port_name;
  // The next available sequence number to use for outgoing user message events
  // originating from this port.
  uint64_t next_sequence_num_to_send;
  // [...]
}
```