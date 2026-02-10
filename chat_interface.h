#pragma once

#include <QtCore/QObject>
#include <QtCore/QStringList>
#include "interface.h"
#include <functional>

// Define a callback type for message handling
using MessageCallback = std::function<void(const std::string&, const std::string&, const std::string&)>;

// Discovery mode enum
enum class DiscoveryMode {
    ExtKadOnly = 0,   // Extended Kademlia only
    StdDiscovery = 1, // Rendezvous + Peer Exchange (no discv5)
    All = 2           // Kad + Rendezvous + Peer Exchange
};

class ChatInterface : public PluginInterface {
public:
    virtual ~ChatInterface() {}

    // Initialize with discovery configuration to avoid race conditions
    // mode: discovery mode (ExtKadOnly, StdDiscovery, All)
    // bootstrapNodes: list of multiaddr strings for peer discovery
    // mixnodes: list of "multiaddr:mixPubKey" strings for mixnode configuration
    Q_INVOKABLE virtual bool initialize(int mode, const QString& bootstrapNodes, const QString& mixnodes) = 0;
    Q_INVOKABLE virtual bool joinChannel(const QString& channelName) = 0;
    Q_INVOKABLE virtual void sendMessage(const QString& channelName, const QString& username, const QString& message) = 0;
    Q_INVOKABLE virtual bool retrieveHistory(const std::string& channelName) = 0;

    // Network metrics
    Q_INVOKABLE virtual bool getMixnodePoolSize() = 0;
    Q_INVOKABLE virtual bool getLightpushPeersCount() = 0;

signals:
    // for now this is required for events, later it might not be necessary if using a proxy
    void eventResponse(const QString& eventName, const QVariantList& data);
};

#define ChatInterface_iid "org.logos.ChatInterface"
Q_DECLARE_INTERFACE(ChatInterface, ChatInterface_iid)
