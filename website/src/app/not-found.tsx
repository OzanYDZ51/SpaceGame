import { Container } from "@/components/ui/Container";
import { Button } from "@/components/ui/Button";

export default function NotFound() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <Container className="text-center">
        <h1 className="text-8xl font-bold text-cyan/20 font-mono mb-4">404</h1>
        <h2 className="text-2xl font-bold uppercase tracking-wider text-text-primary mb-2">
          Secteur inconnu
        </h2>
        <p className="text-text-secondary mb-8">
          Cette zone de l&apos;univers n&apos;a pas encore été cartographiée.
        </p>
        <Button href="/">Retour à l&apos;accueil</Button>
      </Container>
    </div>
  );
}
