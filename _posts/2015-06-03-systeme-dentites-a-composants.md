---
layout: post
title: "Système d'entités à composants"
description: ""
category: Tutos
tags: [c++, c++11, ecs]
---
{% include JB/setup %}

## Introduction

L'ECS, pour Entity Component System, est un type d'architecture qui est presque à la mode aujourd'hui et il faut dire qu'il y a de quoi. Il s'agit d'un type d'architecture qui permet surtout d'éviter les énormes arbres d'héritage.

J'avais lu une phrase sur StackOverflow qui m'avait fait beaucoup réagir:
> Prefer composition over inheritance as it is more malleable / easy to modify later, but do not use a compose-always approach.

En fait, l'abus de l'héritage vient surtout des tutos/cours sur la programmation orientée objet, qui prennent souvent comme exemple une classe mère `Véhicule` et ses deux classes filles `Voiture` et `Moto`. Évidemment, ce n'est pas si mal pour faire comprendre le fonctionnement de la POO, mais ce n'est pas une bonne idée de réutiliser ça dans un jeu plus compliqué.

Par exemple, imaginons qu'on ait une classe `VaisseauSpatial` mais qu'à partir de cette dernière on aimerait créer une centaine de types de vaisseaux différents. En utilisant l'héritage, on risque d'avoir un arbre énorme, compliqué à maintenir, et il est aussi possible que du code soit dupliqué entre deux classes filles (dans le cas où ce dernier n'est pas déplacé dans la classe mère la plus proche, ce qui n'est pas une meilleure idée non plus car on prend le risque d'avoir une classe mère énorme).

Les systèmes d'entité à composants sont là pour nous éviter ce genre de problème, mais comment implémenter ça ? En cherchant sur Internet ce n'est pas vraiment difficile de trouver des articles dessus, mais on se rend vite compte qu'il existe plusieurs types d'implémentations. Par exemple, certains auront une classe `Entity` qui contient directement les composants, d'autres considéreront l'entité comme un ID unique, permettant de récupérer les composants correspondants dans des tableaux.

Pour mon Zelda j'ai choisi la première solution, étant donné que c'est celle qui me paraissait la plus simple à implémenter, et c'est celle que je vais présenter ici.

On a besoin de quoi concrètement pour créer une entité dans un ECS ? De ses composants, c'est tout. Donc on peut faire une classe d'entité qui contiendrait un tableau de composants. Est-ce que ces composants ont besoin d'un classe mère `Composant` ? Pour répondre à cette question, il faudrait déjà savoir ce qu'on va mettre dedans.

## Les composants

Dans pas mal d'implémentations que j'ai pu voir, les composants étaient considérés comme des morceaux de données, un peu à la manière des modèles dans l'architecture MVC. Certains utilisent même uniquement des types de bases (`bool`, `std::pair`, etc...) et associent un nom à chacun de leurs composants, d'autres ont une classe mère Component, et d'autres ne font ni l'un, ni l'autre. Je fais partie de ces derniers.

Tout d'abord, je me suis demandé de quels composants je pourrais avoir besoin. Mes premières idées m'ont poussé à faire un `PositionComponent` et un `MovementComponent`. Le premier contient les coordonnées, la taille et la direction d'une entité, le second contiendra la vélocité, une pile de `Movement` et des flags utiles pour le jeu (`isMoving`, `isBlocked`, ...).

## Les entités

Mais une question s'est alors posée, comment créer une classe `Entity` qui contient des composants de différents types en C++ ? C'est là que j'ai eu une idée: étant donné qu'un `std::shared_ptr` sur `void` appellera toujours le bon destructeur, peu importe le type qu'on lui donne, ce type de pointeur intelligent est du coup vraiment pratique dans notre cas.

Voici ce à quoi je suis arrivé:

{% highlight cpp %}
class SceneObject {
	public:
		SceneObject() = default;
		SceneObject(const SceneObject &) = delete;
		SceneObject(SceneObject &&) = default;
		
		SceneObject &operator=(const SceneObject &) = delete;
		SceneObject &operator=(SceneObject &&) = default;
		
		template<typename T, typename... Args>
		T &set(Args &&...args) {
			m_components[typeid(T)] = std::make_shared<T>(std::forward<Args>(args)...);
			return get<T>();
		}
		
		template<typename T>
		bool has() {
			return m_components.find(typeid(T)) != m_components.end();
		}
		
		template<typename T>
		T &get() {
			if(has<T>()) {
				return *std::static_pointer_cast<T>(m_components[typeid(T)]).get();
			} else {
				throw Exception("SceneObject", (void*)this, "doesn't have a component of type:", typeid(T).name());
			}
		}
		
		template<typename T>
		void remove() {
			m_components.erase(typeid(T));
		}
		
	private:
		std::map<std::type_index, std::shared_ptr<void>> m_components;
};
{% endhighlight %}

Je ne vais pas m'attarder sur ce code, qui, me semble-t-il, est assez simple à comprendre une fois qu'on a assimilé les notions relatives au C++11.

## Fabriques d'entités automatisées

Afin de fabriquer des entités toutes prêtes, comme une épée ou un monstre, il fallait créer des fabriques. Pour cela, j'ai décidé de faire uniquement des classes avec une fonction statique, par exemple:

{% highlight cpp %}
SceneObject ChestFactory::create(u16 tileX, u16 tileY) {
	SceneObject object;
	object.set<PositionComponent>(tileX * 16, tileY * 16, 16, 16);
	
	auto &hitboxComponent = object.set<HitboxComponent>();
	hitboxComponent.addHitbox(0, 0, 16, 16);
	
	return object;
}
{% endhighlight %}

Cette fonction permet de créer une entité, de la paramétrer en lui assignant des composants, et de la retourner pour un usage ultérieur.

Il serait même possible de créer une fabrique unique, qui lirait des fichiers XML (ou JSON, je suis pas raciste) et créerait des entités tout prêtes, sans avoir à écrire une fabrique pour chaque type d'objet. Cette approche a l'avantage d'être vraiment modulable, mais en faisant cela, on rend impossible le fait de créer des comportements sans implémenter une API de scripting.

Maintenant qu'on sait faire des composants et les utiliser pour paramétrer des entités, il faut trouver une solution pour les lire et effectuer des actions dessus en conséquence.

## Les systèmes

Il s'agit ici d'un concept vraiment simple. J'utilise, comme pour les fabriques, des classes statiques. Je vais donner un exemple simple avant de développer:

{% highlight cpp %}
void MovementSystem::process(SceneObject &object) {
	if(object.has<MovementComponent>()) {
		auto &movement = object.get<MovementComponent>();
		
		if(!movement.movements.empty() && movement.movements.top()) {
			movement.movements.top()->process(object);
		}
		
		movement.isBlocked = false;
	}
	
	if(object.has<CollisionComponent>()) {
		object.get<CollisionComponent>().checkCollisions(object);
	}
	
	if(object.has<PositionComponent>() && object.has<MovementComponent>()) {
		auto &position = object.get<PositionComponent>();
		auto &movement = object.get<MovementComponent>();
		
		movement.isMoving = (movement.v.x || movement.v.y) ? true : false;
		
		position.move(movement.v * movement.speed);
		
		movement.v = 0;
	}
}
{% endhighlight %}

Dans un premier temps, on vérifie que l'entité a bien un `MovementComponent` pour pouvoir effectuer le mouvement. Ensuite, on teste si l'entité a un `CollisionComponent` pour appeler une callback qui va vérifier les collisions. Enfin, on vérifie que l'entité a un `PositionComponent` pour lui appliquer le mouvement.

L'utilisation des `System` est vraiment pratique dans la mesure où les composants ne sont pas interdépendants. De plus, chaque `System` a un rôle précis, permettant une meilleure maintenabilité du code. Dans le même ordre d'idée que ce `MovementSystem`, on peut évidemment ajouter un `CollisionSystem`, un `DrawingSystem`, un `BattleSystem`, etc...

Tous les systèmes sont orchestrés par la classe qui est sensée gérer le monde, par exemple `World`, `Scene`, ou par un super-système dans mon cas: `SceneSystem`.

## Conclusion

Ce type d'architecture est vraiment pratique et modulable, facilite la maintenabilité, mais chacun a son implémentation. La mienne ne vous plaira peut-être pas, ou ne sera peut-être pas adaptée pour vos besoins, mais elle était adaptée aux miens.

Si vous avez des idées d'améliorations, ou même une manière totalement différente de procéder, n'hésitez pas à faire un tour dans les commentaires. :)

