import Image from "next/image";

type QuillLogoProps = {
  className?: string;
  priority?: boolean;
};

export function QuillLogo({ className = "brand-mark", priority = false }: QuillLogoProps) {
  return (
    <Image
      src="/brand/quill-logo.svg"
      width={36}
      height={36}
      alt=""
      aria-hidden="true"
      className={className}
      priority={priority}
    />
  );
}
