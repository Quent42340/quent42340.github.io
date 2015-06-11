---
layout: post
title: "Gestion de ressources"
description: ""
category: tutos
tags: [c++, c++11]
---
{% include JB/setup %}

## Introduction

J'ai cherché pendant un moment comme faire un système de gestion de ressources centralisé, et j'ai finalement trouvé. Il s'agit d'une simple classe singleton nommée `ResourceHandler`.

Certes, puisque c'est un singleton je ne pense pas qu'elle puisse être utilisée telle quelle en multithreading, mais je ne pense pas qu'il y ait beaucoup de modifications à faire pour rendre ça possible.

## Quel type de conteneur utiliser ?

J'ai choisi un `std::map<std::string, std::shared_ptr<void>>`, ce qui signifie que chaque ressource a un nom et est gérée par un `std::shared_ptr<void>`. Petit rappel, le `std::shared_ptr<void>` permet d'appeler le destructeur du bon type durant la destruction de l'objet.

## Le code

Voilà le code complet du `ResourceHandler`:

{% highlight cpp %}
class ResourceHandler {
	public:
		template<typename T, typename... Args>
		T &add(const std::string &name, Args &&...args) {
			if(has(name)) {
				throw EXCEPTION("A resource of type", typeid(T).name(), "already exists with name:", name);
			}
			
			m_resources[name] = std::make_shared<T>(std::forward<Args>(args)...);
			
			return get<T>(name);
		}
		
		bool has(const std::string &name) {
			return m_resources.find(name) != m_resources.end();
		}
		
		template<typename T>
		T &get(const std::string &name) {
			if(!has(name)) {
				throw EXCEPTION("Unable to find resource with name:", name);
			}
			
			return *std::static_pointer_cast<T>(m_resources[name]);
		}
		
		template<typename ResourceLoader>
		static void loadConfigFile(const std::string &xmlFilename) {
			ResourceLoader loader;
			loader.load(xmlFilename, getInstance());
		}
		
		static ResourceHandler &getInstance() {
			static ResourceHandler instance;
			return instance;
		}
		
	private:
		ResourceHandler() = default;
		
		std::map<std::string, std::shared_ptr<void>> m_resources;
};
{% endhighlight %}

Vous avez certainement remarqué la fonction `loadConfigFile`, elle permet d'appeller une classe qui va charger des ressources à partir d'un fichier XML. C'est vraiment pratique dans la mesure où la configuration de chaque type de ressource est totalement différente.

Le `ResourceHandler` s'utilise de cette manière:

{% highlight cpp %}
ResourceHandler::getInstance().loadConfigFile<TextureLoader>("config/textures.xml");

Texture &playerTexture = ResourceHandler::getInstance().get<Texture>("playerTexture");
{% endhighlight %}

Pour ajouter une ressource on envoie les paramètres du constructeur dans `add`:

{% highlight cpp %}
ResourceHandler::getInstance().add<Texture>("playerTexture", "graphics/player.png");
{% endhighlight %}

Voici un exemple de loader, ici `XMLFile` est un wrapper de la classe `XMLDocument` de tinyxml2:

{% highlight cpp %}
class ResourceLoader {
	public:
		virtual void load(const std::string &xmlFilename, ResourceHandler &handler) = 0;
};

class TextureLoader : public ResourceLoader {
	public:
		void load(const std::string &xmlFilename, ResourceHandler &handler) {
			XMLFile doc(xmlFilename);
			
			XMLElement *textureElement = doc.FirstChildElement("textures").FirstChildElement("texture").ToElement();
			while(textureElement) {
				std::string folder = textureElement->Attribute("folder");
				std::string name = textureElement->Attribute("name");
				
				std::string filename = "graphics/" + folder + "/" + name + ".png";
				
				handler.add<Texture>(folder + "-" + name, filename);
				
				textureElement = textureElement->NextSiblingElement("texture");
			}
		}
};
{% endhighlight %}

